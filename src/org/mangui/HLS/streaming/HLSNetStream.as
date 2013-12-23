package org.mangui.HLS.streaming {


    import org.mangui.HLS.*;
    import org.mangui.HLS.muxing.*;
    import org.mangui.HLS.streaming.*;
    import org.mangui.HLS.utils.*;
    import flash.net.*;
    import flash.utils.*;


    /** Class that keeps the buffer filled. **/
    public class HLSNetStream extends NetStream {
        /** Reference to the framework controller. **/
        private var _hls:HLS;
        /** The buffer with video tags. **/
        private var _buffer:Vector.<Tag>;
        /** The fragment loader. **/
        private var _fragmentLoader:FragmentLoader;
        /** Store that a fragment load is in progress. **/
        private var _fragment_loading:Boolean;
        /** means that last fragment of a VOD playlist has been loaded */
        private var _reached_vod_end:Boolean;
        /** Interval for checking buffer and position. **/
        private var _interval:Number;
        /** requested start position **/
        private var _seek_position_requested:Number = 0;
         /** real start position , retrieved from first fragment **/
        private var _seek_position_real:Number;
        /** initial seek offset, difference between real seek position and first fragment start time **/
        private var _seek_offset:Number;
        /** Current play position (relative position from beginning of sliding window) **/
        private var _playback_current_position:Number;
        /** playlist sliding (non null for live playlist) **/
        private var _playlist_sliding_duration:Number;
        /** array of buffer start PTS (indexed by continuity) */
        private var _buffer_start_pts:Array;
        /** array of buffer last PTS (indexed by continuity) **/
        private var _buffer_last_pts:Array;
         /** previous buffer time. **/
        private var _last_buffer:Number;
        /** Current playback state. **/
        private var _state:String;
        /** The last tag that was appended to the buffer. **/
        private var _buffer_current_index:Number;
        /** max buffer length (default 60s)**/
        private var _buffer_max_len:Number=60;
        /** playlist duration **/
        private var _playlist_duration:Number=0;

        private var _was_playing:Boolean = false;
        /** Create the buffer. **/
        
        public function HLSNetStream(connection:NetConnection, hls:HLS, fragmentLoader:FragmentLoader):void {
            super(connection);
            super.inBufferSeek = true;
            _hls = hls;
            _fragmentLoader = fragmentLoader;
            _hls.addEventListener(HLSEvent.LAST_VOD_FRAGMENT_LOADED,_lastVODFragmentLoadedHandler);
            _hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED,_playlistDurationUpdated);
            _setState(HLSStates.IDLE);
        };


        /** Check the bufferlength. **/
        private function _checkBuffer():void {
          //Log.txt("checkBuffer");
            var buffer:Number = 0;
            // Calculate the buffer and position.
            if(_buffer.length) {
               buffer = this.bufferLength;
               /** Absolute playback position (start position + play time) **/
               var playback_absolute_position:Number = (Math.round(super.time*100 + _seek_position_real*100)/100);
               /** Relative playback position (Absolute Position - playlist sliding, non null for Live Playlist) **/
               var playback_relative_position:Number = playback_absolute_position-_playlist_sliding_duration;
               
               // only send media time event if data has changed
               if(playback_relative_position != _playback_current_position || buffer !=_last_buffer) {
                  if (playback_relative_position <0) {
                     playback_relative_position = 0;
                  }
                  _playback_current_position = playback_relative_position;
                  _last_buffer = buffer;
                  _hls.dispatchEvent(new HLSEvent(HLSEvent.MEDIA_TIME,new HLSMediatime(_playback_current_position, _playlist_duration, buffer)));
               }
            }
            //Log.txt("checkBuffer,loading,needReload,_reached_vod_end,buffer,maxBufferLength:"+ _fragment_loading + "/" + _fragmentLoader.needReload() + "/" + _reached_vod_end + "/" + buffer + "/" + _buffer_max_len);
            // Load new tags from fragment, 
            if(_reached_vod_end == false &&                                         // if we have not reached the end of a VoD playlist AND 
               ((_buffer_max_len == 0) || (buffer < _buffer_max_len)) &&            // if the buffer is not full AND
               ((!_fragment_loading) || _fragmentLoader.needReload() == true)) {    // ( if no fragment is being loaded currently OR if a fragment need to be reloaded
                var loadstatus:Number;
                if(super.time == 0 && _buffer.length == 0) {
                // just after seek, load first fragment
                  loadstatus = _fragmentLoader.loadfirstfragment(_seek_position_requested,_loaderCallback);
                } else {
                  loadstatus = _fragmentLoader.loadnextfragment(buffer,_loaderCallback);
                }
                if (loadstatus == 0) {
                  // good, new fragment being loaded
                  _fragment_loading = true;
                } else  if (loadstatus < 0) {
                  /* it means PTS requested is smaller than playlist start PTS.
                     it could happen on live playlist :
                     - if bandwidth available is lower than lowest quality needed bandwidth
                     - after long pause
                     seek to offset 0 to force a restart of the playback session  */
                  Log.txt("long pause on live stream or bad network quality");
                  seek(0);
                  return;
               } else if(loadstatus > 0) {
                  //seqnum not available in playlist
                  _fragment_loading = false;
               }
            }
            // try to append data into NetStream
            //if we are already in PLAYING state, OR
            if((_state == HLSStates.PLAYING) || 
            //if we are in Buffering State, with enough buffer data (at least 10s) OR at the end of a VOD playlist
               (_state == HLSStates.BUFFERING && (buffer > 10 || _reached_vod_end)))
             {
                //Log.txt("appending data into NetStream");
                while(_buffer_current_index < _buffer.length && // append data until we drain our _buffer[] array AND
                      super.bufferLength < 10) { // that NetStream Buffer contains at least 10s
                    try {
                        if(_buffer[_buffer_current_index].type == Tag.DISCONTINUITY) {
                          super.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
                          super.appendBytes(FLV.getHeader());
                      } else {
                          super.appendBytes(_buffer[_buffer_current_index].data);
                      }
                    } catch (error:Error) {
                        _errorHandler(new Error(_buffer[_buffer_current_index].type+": "+ error.message));
                    }
                    // Last tag done? Then append sequence end.
                    if (_reached_vod_end ==true && _buffer_current_index == _buffer.length - 1) {
                        super.appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
                        super.appendBytes(new ByteArray());
                    }
                    _buffer_current_index++;
                }
            }
            // Set playback state and complete.
            if(super.bufferLength < 3) {
                if(super.bufferLength == 0 && _reached_vod_end ==true) {
                    clearInterval(_interval);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYBACK_COMPLETE));
                    _setState(HLSStates.IDLE);
                } else if(_state == HLSStates.PLAYING) {
                    !_reached_vod_end && _setState(HLSStates.BUFFERING);
                }
            } else if (_state == HLSStates.BUFFERING) {

                if(_was_playing)
                _setState(HLSStates.PLAYING);
                else
                    pause();
            }
        };

        /** Dispatch an error to the controller. **/
        private function _errorHandler(error:Error):void {
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR,error.toString()));
        };


        /** Return the current playback state. **/
        public function getPosition():Number {
            return _playback_current_position;
        };


        /** Return the current playback state. **/
        public function getState():String {
            return _state;
        };


        /** Add a fragment to the buffer. **/
        private function _loaderCallback(tags:Vector.<Tag>,min_pts:Number,max_pts:Number, hasDiscontinuity:Boolean, start_offset:Number):void {
            // flush already injected Tags and restart index from 0
            _buffer = _buffer.slice(_buffer_current_index);
            _buffer_current_index = 0;
            
            var seek_pts:Number = min_pts + (_seek_position_requested-start_offset)*1000;
            if (_seek_position_real == Number.NEGATIVE_INFINITY) {
               _seek_position_real = _seek_position_requested < start_offset ? start_offset : _seek_position_requested;
               _seek_offset = _seek_position_real - start_offset;
            }
            /* check live playlist sliding here :
              _seek_position_real + getTotalBufferedDuration()  should be the start_position of the new fragment if the
              playlist is not sliding
              => live playlist sliding is the difference between these values */
              _playlist_sliding_duration = (_seek_position_real + getTotalBufferedDuration()) - start_offset - _seek_offset;

            /* if first fragment loaded, or if discontinuity, record discontinuity start PTS, and insert discontinuity TAG */
            if(hasDiscontinuity) {
              _buffer_start_pts.push(min_pts);
              _buffer_last_pts.push(max_pts);
              _buffer.push(new Tag(Tag.DISCONTINUITY,min_pts,min_pts,false));
            } else {
              // same continuity than previously, update its max PTS
              _buffer_last_pts[_buffer_last_pts.length-1] = max_pts;
            }
            
            tags.sort(_sortTagsbyDTS);
            for each (var t:Tag in tags) {
                _filterTag(t,seek_pts) && _buffer.push(t);
            }
            Log.txt("Loaded offset/duration/sliding/discontinuity:"+start_offset.toFixed(2) + "/" +((max_pts-min_pts)/1000).toFixed(2) + "/" + _playlist_sliding_duration.toFixed(2)+ "/" + hasDiscontinuity );
            _fragment_loading = false;
        };


        /** return total buffered duration since seek() call 
         needed to compute remaining buffer duration
        */
        private function getTotalBufferedDuration():Number {
          var bufSize:Number = 0;
          if(_buffer_start_pts != null) {
            /* duration of all the data already pushed into Buffer = sum of duration per continuity index */
            for(var i:Number=0; i < _buffer_start_pts.length ; i++) {
              bufSize+=_buffer_last_pts[i]-_buffer_start_pts[i];
            }
          }
          bufSize/=1000;
          return bufSize;
        }
      
        private function _lastVODFragmentLoadedHandler(event:HLSEvent):void {
          _reached_vod_end = true;
        }

        private function _playlistDurationUpdated(event:HLSEvent):void {
          _playlist_duration = event.duration;
        }
        
        /** Change playback state. **/
        private function _setState(state:String):void {
            if(state != _state) {
                _state = state;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.STATE,_state));
            }
        };


        /** Sort the buffer by tag. **/
        private function _sortTagsbyDTS(x:Tag,y:Tag):Number {
            if(x.dts < y.dts) {
                return -1;
            } else if (x.dts > y.dts) {
                return 1;
            } else {
                if(x.type == Tag.AVC_HEADER || x.type == Tag.AAC_HEADER) {
                    return -1;
                } else if (y.type == Tag.AVC_HEADER || y.type == Tag.AAC_HEADER) {
                    return 1;
                } else {
                    if(x.type == Tag.AVC_NALU) {
                        return -1;
                    } else if (y.type == Tag.AVC_NALU) {
                        return 1;
                    } else {
                        return 0;
                    }
                }
            }
        };

        /**
         *
         * Filter tag by type and pts for accurate seeking.
         *
         * @param tag
         * @param pts Destination pts
         * @return
         */
        private function _filterTag(tag:Tag,pts:Number = 0):Boolean{
            if(tag.type == Tag.AAC_HEADER || tag.type == Tag.AVC_HEADER || tag.type == Tag.AVC_NALU){
              if(tag.pts < pts)
               tag.pts = tag.dts = pts;
              return true;
            }
            return tag.pts >= pts;
        }

    override public function play(...args):void 
    {
      var _playStart:Number;
      if (args.length >= 2)
      {
        _playStart = Number(args[1]);
      } else {
            _playStart = 0;
         }         
      Log.txt("HLSNetStream:play("+_playStart+")");
      seek(_playStart);
    }

    override public function play2(param : NetStreamPlayOptions):void 
    {
      Log.txt("HLSNetStream:play2("+param.start+")");
      seek(param.start);
    }

    /** Pause playback. **/
    override public function pause():void {
        Log.txt("HLSNetStream:pause");
        if(_state == HLSStates.PLAYING || _state == HLSStates.BUFFERING) {
            clearInterval(_interval);
            super.pause();
            _setState(HLSStates.PAUSED);
        }
    };
    
    /** Resume playback. **/
    override public function resume():void {
         Log.txt("HLSNetStream:resume");
        if(_state == HLSStates.PAUSED) {
            clearInterval(_interval);
            super.resume();
            _interval = setInterval(_checkBuffer,100);
            _setState(HLSStates.PLAYING);
        }
    };

    /** get Buffer Length  **/
    override public function get bufferLength():Number {
      /* remaining buffer is total duration buffered since beginning minus playback time */
      return getTotalBufferedDuration() - super.time;
    };

    /** get max Buffer Length  **/
    public function get maxBufferLength():Number {
      return _buffer_max_len;
    };

    /** set max Buffer Length  **/
    public function set maxBufferLength(new_len:Number):void {
      _buffer_max_len = new_len;
    };

        /** Start playing data in the buffer. **/
        override public function seek(position:Number):void {
               Log.txt("HLSNetStream:seek("+position+")");
               _buffer = new Vector.<Tag>();
               _fragmentLoader.clearLoader();
               _fragment_loading = false;
               _buffer_current_index = 0;
               _buffer_start_pts = new Array();
               _buffer_last_pts = new Array();
                _seek_position_requested = position;
                super.close();
                super.play(null);
                super.appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK);
               _reached_vod_end = false;
               _seek_position_real = Number.NEGATIVE_INFINITY;
               _last_buffer = 0;
               _was_playing = (_state == HLSStates.PLAYING) || (_state == HLSStates.IDLE);
               _setState(HLSStates.BUFFERING);
               clearInterval(_interval);
               _interval = setInterval(_checkBuffer,100);
        };


        /** Stop playback. **/
        override public function close():void {
            Log.txt("HLSNetStream:close");
            super.close();
            _fragment_loading = false;
            clearInterval(_interval);
            _setState(HLSStates.IDLE);
        };
    }
}