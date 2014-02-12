package org.mangui.HLS.streaming {


    import org.mangui.HLS.*;
    import org.mangui.HLS.muxing.*;
    import org.mangui.HLS.parsing.*;
    import org.mangui.HLS.streaming.*;
    import org.mangui.HLS.utils.*;

    import com.hurlant.util.Hex;

//CONFIG::AS3HTTPCLIENT {
//    import com.adobe.net.URI;
//    import org.httpclient.HttpClient;
//    import org.httpclient.HttpRequest;
//    import org.httpclient.http.Get;
//    import org.httpclient.events.HttpListener;
//    import org.httpclient.events.HttpDataEvent;
//    import org.httpclient.events.HttpStatusEvent;
//}
    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;

    /** Class that fetches fragments. **/
    public class FragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls:HLS;
        /** reference to auto level manager */
        private var _autoLevelManager:AutoLevelManager;
        /** has manifest just being reloaded **/
        private var _manifest_just_loaded:Boolean = false;
        /** overall processing bandwidth of last loaded fragment (fragment size divided by processing duration) **/
        private var _last_bandwidth:int = 0;
        /** overall processing time of the last loaded fragment (loading+decrypting+parsing) **/
        private var _last_process_duration:Number = 0;
        /** duration of the last loaded fragment **/
        private var _last_segment_duration:Number = 0;
        /** last loaded fragment size **/
        private var _last_segment_size:Number = 0;
        /** duration of the last loaded fragment **/
        private var _last_segment_start_pts:Number = 0;
        /** continuity counter of the last fragment load. **/
        private var _last_segment_continuity_counter:Number = 0;
        /** program date of the last fragment load. **/
        private var _last_segment_program_date:Number = 0;
        /** decrypt URL of last segment **/
        private var _last_segment_decrypt_key_url:String;
        /** IV of  last segment **/
        private var _last_segment_decrypt_iv:ByteArray;
        /** last updated level. **/
        private var _last_updated_level:Number = 0;
        /** Callback for passing forward the fragment tags. **/
        private var _callback:Function;
        /** sequence number that's currently loading. **/
        private var _seqnum:Number;
        /** start level **/
        private var _start_level:int;
        /** Quality level of the last fragment load. **/
        private var _level:int;
        /* overrided quality_manual_level level */
        private var _manual_level:int = -1;
        /** Reference to the manifest levels. **/
        private var _levels:Vector.<Level>;
        /** Util for loading the fragment. **/
        private var _fragstreamloader:URLStream;
        /** Util for loading the key. **/
        private var _keystreamloader:URLStream;
        /** key map **/
        private var _keymap:Object = new Object();
        /** fragment bytearray **/
        private var _fragByteArray:ByteArray;
        /** fragment bytearray write position **/
        private var _fragWritePosition:Number;
        /** fragment byte range start offset **/
        private var _frag_byterange_start_offset:Number;
        /** fragment byte range end offset **/
        private var _frag_byterange_end_offset:Number;
        /** AES decryption instance **/
        private var _decryptAES:AES;
        /** Time the loading started. **/
        private var _frag_loading_start_time:Number;
        /** Time the decryption started. **/
        private var _frag_decrypt_start_time:Number;
        /** Time the parsing started. **/
        //private var _frag_parsing_start_time:Number;
        /** Did the stream switch quality levels. **/
        private var _switchlevel:Boolean;
        /** Did a discontinuity occurs in the stream **/
        private var _hasDiscontinuity:Boolean;
        /** Width of the stage. **/
        private var _width:Number = 480;
        /* flag handling load cancelled (if new seek occurs for example) */
        private var _cancel_load:Boolean;
        /* variable to deal with IO Error retry */
        private var _bIOError:Boolean;
        private var _nIOErrorDate:Number=0;

        /** boolean to track playlist PTS in loading */
        private var _pts_loading_in_progress:Boolean=false;
        /** boolean to indicate that PTS of new playlist has just been loaded */
        private var _pts_just_loaded:Boolean=false;
        /** boolean to indicate whether Buffer could request new fragment load **/
        private var _need_reload:Boolean=true;

        /** Reference to the alternate audio track list. **/
        private var _altAudioTrackLists:Vector.<AltAudioTrack>;
        /** list of audio tracks from demuxed fragments **/
        private var _audioTracksfromDemux:Vector.<HLSAudioTrack>;
        /** list of audio tracks from Manifest, matching with current level **/
        private var _audioTracksfromManifest:Vector.<HLSAudioTrack>;
        /** merged audio tracks list **/
        private var _audioTracks:Vector.<HLSAudioTrack>;
        /** current audio track id **/
        private var _audioTrackId:Number;
        
        public var startFromLowestLevel:Boolean=false;

        /** Create the loader. **/
        public function FragmentLoader(hls:HLS):void {
            _hls = hls;
            _autoLevelManager = new AutoLevelManager(hls);
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_UPDATED,_levelUpdatedHandler);
            _hls.addEventListener(HLSEvent.ALT_AUDIO_TRACKS_LIST_CHANGE,_altAudioTracksListChangedHandler);
            _fragstreamloader = new URLStream();
            _fragstreamloader.addEventListener(IOErrorEvent.IO_ERROR, _fragErrorHandler);
            _fragstreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _fragErrorHandler);
            _fragstreamloader.addEventListener(ProgressEvent.PROGRESS,_fragProgressHandler);
            _fragstreamloader.addEventListener(HTTPStatusEvent.HTTP_STATUS,_fragHTTPStatusHandler);
            _keystreamloader = new URLStream();
            _keystreamloader.addEventListener(IOErrorEvent.IO_ERROR, _keyErrorHandler);
            _keystreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _keyErrorHandler);
            _keystreamloader.addEventListener(Event.COMPLETE, _keyCompleteHandler);
        };

        public function setAudioTrack(num:Number):void {
            if (_audioTrackId != num) {
                _audioTrackId = num;
                var ev:HLSEvent = new HLSEvent(HLSEvent.AUDIO_TRACK_CHANGE);
                ev.audioTrack = _audioTrackId;
                _hls.dispatchEvent(ev);
                Log.info('Setting audio track to ' + num);
            }
        }

        public function getAudioTrackId():Number {
            return _audioTrackId;
        }

        public function getAudioTrackList():Vector.<HLSAudioTrack> {
            return _audioTracks;
        }

        /** key load completed. **/
        private function _keyCompleteHandler(event:Event):void {
            Log.debug("key loading completed");
            // Collect key data
            if( _keystreamloader.bytesAvailable > 0 ) {
              var keyData:ByteArray = new ByteArray();
              _keystreamloader.readBytes(keyData,0,0);
              var frag:Fragment = _levels[_level].getFragmentfromSeqNum(_seqnum);
              _keymap[frag.decrypt_url] = keyData;
              // now load fragment
              try {
                 Log.debug("loading fragment:" + frag.url);
                 _fragstreamloader.load(new URLRequest(frag.url));
              } catch (error:Error) {
                  _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, error.message));
              }
            }
        };

        private function _fraghandleIOError(message:String):void {
            /* usually, errors happen in two situations :
            - bad networks  : in that case, the second or third reload of URL should fix the issue
            - live playlist : when we are trying to load an out of bound fragments : for example,
                              the playlist on webserver is from SN [51-61]
                              the one in memory is from SN [50-60], and we are trying to load SN50.
                              we will keep getting 404 error if the HLS server does not follow HLS spec,
                              which states that the server should keep SN50 during EXT-X-TARGETDURATION period
                              after it is removed from playlist
                              in the meantime, ManifestLoader will keep refreshing the playlist in the background ...
                              so if the error still happens after EXT-X-TARGETDURATION, it means that there is something wrong
                              we need to report it.
            */
            Log.error("I/O Error while loading fragment:"+message);
            if(_bIOError == false) {
              _bIOError=true;
              _nIOErrorDate = new Date().valueOf();
            } else if((new Date().valueOf() - _nIOErrorDate) > 1000*_levels[_last_updated_level].averageduration ) {
              _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, "I/O Error :" + message));
            }
            _need_reload = true;
        }

        private function _fragHTTPStatusHandler(event:HTTPStatusEvent):void {
          if(event.status >= 400) {
            _fraghandleIOError("HTTP Status:"+event.status.toString());
          }
        }

        private function _fragProgressHandler(event:ProgressEvent):void {
          if(_fragByteArray == null) {
            _fragByteArray = new ByteArray();
            _last_segment_size = event.bytesTotal;
            _fragWritePosition = 0;
            //decrypt data if needed
            if (_last_segment_decrypt_key_url != null) {
              _frag_decrypt_start_time = new Date().valueOf();
              _decryptAES = new AES(_keymap[_last_segment_decrypt_key_url],_last_segment_decrypt_iv);
              _decryptAES.decrypt(_fragByteArray,_fragDecryptCompleteHandler);
            } else {
              _decryptAES = null;
            }
          }
          // append new bytes into fragByteArray
          _fragByteArray.position = _fragWritePosition;
          _fragstreamloader.readBytes(_fragByteArray,_fragWritePosition,0);
          _fragWritePosition=_fragByteArray.length;
          Log.debug2("bytesLoaded/bytesTotal:"+event.bytesLoaded + "/"+ event.bytesTotal);
          if(_decryptAES != null) {	  
            _decryptAES.notifyappend();
          }
          if(event.bytesLoaded == event.bytesTotal) {
            Log.debug("loading completed");
            _cancel_load = false;
            if(_decryptAES != null) {
              _decryptAES.notifycomplete();
            } else {
              _fragDemux(_fragByteArray);
            }
          }
        }

    private function _fragDecryptCompleteHandler(data:ByteArray):void {
      var decrypt_duration:Number = (new Date().valueOf() - _frag_decrypt_start_time);
      _decryptAES = null;
      Log.debug("Decrypted     duration/length/speed:"+decrypt_duration+ "/" + data.length + "/" + ((8000*data.length/decrypt_duration)/1024).toFixed(0) + " kb/s");
      _fragDemux(data);
    }

      private function _fragDemux(data : ByteArray) : void {
         // _frag_parsing_start_time = new Date().valueOf();
         
         /* deal with byte range if any specified */
         if (_frag_byterange_start_offset !=-1) {
            Log.debug("trim byte range, start/end offset:" + _frag_byterange_start_offset + "/" + _frag_byterange_end_offset);
            var ba:ByteArray = new ByteArray();
            data.position = _frag_byterange_start_offset;
            data.readBytes(ba,0,_frag_byterange_end_offset-_frag_byterange_start_offset);
            data = ba;
         }
         /* probe file type */
         data.position = 0;
         Log.debug("probe fragment type");
         if (TS.probe(data) == true) {
            Log.debug("MPEG2-TS found");
            var audio_pid:Number;
            var audio_extract:Boolean;
            if(_audioTrackId ==-1) {
               // unknown, will be retrieved from demux
               audio_pid = -1;
               audio_extract = true;
            } else {
               var track:HLSAudioTrack = _audioTracks[_audioTrackId];
               if(track.source == HLSAudioTrack.FROM_DEMUX) {
                  audio_pid = _audioTracks[_audioTrackId].id;
                  audio_extract = true;
               } else {
                  audio_pid = -1;
                  audio_extract = false;
               }
            }
            new TS(data, _fragReadHandler,audio_extract,audio_pid);
         } else if (AAC.probe(data) == true) {
            Log.debug("AAC ES found");
            new AAC(data,_fragReadHandler);
         }else if (MP3.probe(data) == true) {
            Log.debug("MP3 ES found");
            new MP3(data,_fragReadHandler);
         } else {
            Log.error("unknown fragment type");
            if(Log.LOG_DEBUG2_ENABLED) {
              data.position = 0;
              var ba2:ByteArray = new ByteArray();
              data.readBytes(ba2,0,512);
              Log.debug2("frag dump(512 bytes)");
              Log.debug2(Hex.fromArray(ba2));
            }
            // invalid fragment
            _fraghandleIOError("invalid content received");
            return;
         }
      }

		/** Kill any active load **/
		public function clearLoader():void {
			if(_fragstreamloader.connected) {
				_fragstreamloader.close();
			}
			if(_decryptAES) {
			 _decryptAES.cancel(); 
			 _decryptAES = null;
			}
			_fragByteArray = null;
			_cancel_load = true;
      _bIOError = false;
		}


        /** Catch IO and security errors. **/
        private function _keyErrorHandler(event:ErrorEvent):void {
          _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, "cannot load key:" + event.text));
        };

        /** Catch IO and security errors. **/
        private function _fragErrorHandler(event:ErrorEvent):void {
          _fraghandleIOError(event.text);
        };

        public function needReload():Boolean {
          return _need_reload;
        };

        /** Get the current QOS metrics. **/
        public function getMetrics():HLSMetrics {
            return new HLSMetrics(_level, _last_bandwidth, _width);
        };

       private function updateLevel(buffer:Number):Number {
          var level:Number;
          if(_manifest_just_loaded) {
            level = _start_level;
          } else if(_bIOError == true) {
            /* in case IO Error has been raised, stick to same level */
            level = _level;
          /* in case fragment was loaded for PTS analysis, stick to same level */
          } else if(_pts_just_loaded == true) {
            _pts_just_loaded = false;
            level = _level;
            /* in case we are switching levels (waiting for playlist to reload) or seeking , stick to same level */
          } else if(_switchlevel == true) {
            level = _level;
          } else if (_manual_level == -1 ) {
            level = _autoLevelManager.getnextlevel(_level,buffer,_last_segment_duration,_last_process_duration,_last_bandwidth);
          } else {
            level = _manual_level;
          }
          if(level != _level || _manifest_just_loaded) {
            _level = level;
            _switchlevel = true;
            _hls.dispatchEvent(new HLSEvent(HLSEvent.QUALITY_SWITCH,_level));
          }
          return level;
       }

        public function loadfirstfragment(position:Number,callback:Function):Number {
            Log.debug("loadfirstfragment(" + position + ")");
             if(_fragstreamloader.connected) {
                _fragstreamloader.close();
            }
            // reset IO Error when loading first fragment
            _bIOError = false;
            _need_reload = false;
            _switchlevel = true;
            updateLevel(0);

            // check if we received playlist for new level. if live playlist, ensure that new playlist has been refreshed
            if ((_levels[_level].fragments.length == 0) || (_hls.getType() == HLSTypes.LIVE && _last_updated_level != _level)) {
              // playlist not yet received
              Log.debug("loadfirstfragment : playlist not received for level:"+_level);
              return 1;
            }

            if (_hls.getType() == HLSTypes.LIVE) {
               var seek_position:Number;
               /* follow HLS spec :
                  If the EXT-X-ENDLIST tag is not present
                  and the client intends to play the media regularly (i.e. in playlist
                  order at the nominal playback rate), the client SHOULD NOT
                  choose a segment which starts less than three target durations from
                  the end of the Playlist file */
               var maxLivePosition:Number = Math.max(0,_levels[_level].duration -3*_levels[_level].averageduration);
               if (position == 0) {
                  // seek 3 fragments from end
                  seek_position = maxLivePosition;
               } else {
                  seek_position = Math.min(position,maxLivePosition);
               }
               Log.debug("loadfirstfragment : requested position:" + position + ",seek position:"+seek_position);
               position = seek_position;
            }
            var seqnum:Number= _levels[_level].getSeqNumBeforePosition(position);
            _callback = callback;
            _frag_loading_start_time = new Date().valueOf();
            var frag:Fragment = _levels[_level].getFragmentfromSeqNum(seqnum);
            _seqnum = seqnum;
            _hasDiscontinuity = true;
            _last_segment_continuity_counter = frag.continuity;
            _last_segment_program_date = frag.program_date;
            Log.debug("Loading       "+ _seqnum +  " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level "+ _level);
            _loadfragment(frag);
            return 0;
        }

        /** Load a fragment **/
        public function loadnextfragment(buffer:Number,callback:Function):Number {
          Log.debug("loadnextfragment(buffer):(" + buffer+ ")");

            if(_fragstreamloader.connected) {
                _fragstreamloader.close();
            }
            // in case IO Error reload same fragment
            if(_bIOError) {
              _seqnum--;
            }
            _need_reload = false;

            updateLevel(buffer);
            // check if we received playlist for new level. if live playlist, ensure that new playlist has been refreshed
            if ((_levels[_level].fragments.length == 0) || (_hls.getType() == HLSTypes.LIVE && _last_updated_level != _level)) {
              // playlist not yet received
              Log.debug("loadnextfragment : playlist not received for level:"+_level);
              return 1;
            }

            var new_seqnum:Number;
            var last_seqnum:Number = -1;
            var log_prefix:String;
            var frag:Fragment;

            if(_switchlevel == false || _last_segment_continuity_counter == -1) {
              last_seqnum = _seqnum;
            } else  { // level switch
              // trust program-time : if program-time defined in previous loaded fragment, try to find seqnum matching program-time in new level.
              if(_last_segment_program_date) {
                last_seqnum = _levels[_level].getSeqNumFromProgramDate(_last_segment_program_date);
                Log.debug("loadnextfragment : getSeqNumFromProgramDate(level,date,cc:"+_level+","+_last_segment_program_date+")="+last_seqnum);
              }
              if(last_seqnum == -1) {
                // if we are here, it means that no program date info is available in the playlist. try to get last seqnum position from PTS + continuity counter
                last_seqnum = _levels[_level].getSeqNumNearestPTS(_last_segment_start_pts,_last_segment_continuity_counter);
                Log.debug("loadnextfragment : getSeqNumNearestPTS(level,pts,cc:"+_level+","+_last_segment_start_pts+","+_last_segment_continuity_counter+")="+last_seqnum);
                if (last_seqnum == -1) {
                // if we are here, it means that we have no PTS info for this continuity index, we need to do some PTS probing to find the right seqnum
                  /* we need to perform PTS analysis on fragments from same continuity range
                  get first fragment from playlist matching with criteria and load pts */
                  last_seqnum = _levels[_level].getFirstSeqNumfromContinuity(_last_segment_continuity_counter);
                  Log.debug("loadnextfragment : getFirstSeqNumfromContinuity(level,cc:"+_level+","+_last_segment_continuity_counter+")="+last_seqnum);
                  if (last_seqnum == Number.NEGATIVE_INFINITY) {
                    // playlist not yet received
                    return 1;
                  }
                  /* when probing PTS, take previous sequence number as reference if possible */
                  new_seqnum=Math.min(_seqnum+1,_levels[_level].getLastSeqNumfromContinuity(_last_segment_continuity_counter));
                  new_seqnum = Math.max(new_seqnum,_levels[_level].getFirstSeqNumfromContinuity(_last_segment_continuity_counter));
                    _pts_loading_in_progress = true;
                    log_prefix = "analyzing PTS ";
                }
              }
            }

            if(_pts_loading_in_progress == false) {
              if(last_seqnum == _levels[_level].end_seqnum) {
              // if last segment was last fragment of VOD playlist, notify last fragment loaded event, and return
              if (_hls.getType() == HLSTypes.VOD)
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
              return 1;
              } else {
                // if previous segment is not the last one, increment it to get new seqnum
                new_seqnum = last_seqnum + 1;
                if(new_seqnum < _levels[_level].start_seqnum) {
                  // we are late ! report to caller
                  return -1;
                }
                frag = _levels[_level].getFragmentfromSeqNum(new_seqnum);
                if (frag == null) {
                  Log.warn("error trying to load "  + new_seqnum +  " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level "+ _level);
                  return 1;
                }
                // update program date
                _last_segment_program_date = frag.program_date;
                // check whether there is a discontinuity between last segment and new segment
                _hasDiscontinuity = (frag.continuity != _last_segment_continuity_counter);
                // update discontinuity counter
                _last_segment_continuity_counter = frag.continuity;
                log_prefix = "Loading       ";
              }
            }
            _seqnum = new_seqnum;
            _callback = callback;
            _frag_loading_start_time = new Date().valueOf();
            frag = _levels[_level].getFragmentfromSeqNum(_seqnum);
            Log.debug(log_prefix + _seqnum +  " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level "+ _level);
            _loadfragment(frag);
            return 0;
        };
        
        private function _loadfragment(frag:Fragment):void {
            _last_segment_decrypt_key_url = frag.decrypt_url;
            _frag_byterange_start_offset = frag.byterange_start_offset;
            _frag_byterange_end_offset = frag.byterange_end_offset;
            if(_last_segment_decrypt_key_url != null && (_keymap[_last_segment_decrypt_key_url] == undefined)) {
              _last_segment_decrypt_iv = frag.decrypt_iv;
              // load key
              Log.debug("loading key:" + _last_segment_decrypt_key_url);
              _keystreamloader.load(new URLRequest(_last_segment_decrypt_key_url));
            } else {
              try {
                 _fragByteArray = null;
                  Log.debug("loading fragment:" + frag.url);
                 _fragstreamloader.load(new URLRequest(frag.url));
                  //if (frag.byterange_start_offset ==-1) {
                  //  _fragstreamloader.load(new URLRequest(frag.url));
                  //} else {
                  //   // use as3httpclientlib for Range Request
                  //   var client:HttpClient = new HttpClient();
                  //   client.listener.onData = function(event:HttpDataEvent):void { 
                  //      _fragDemux(event.bytes);
                  //    };
                  //   client.listener.onError = _fragErrorHandler;
                  //   client.listener.onStatus = function(event:HttpStatusEvent):void {
                  //   };
                  //   var request:HttpRequest = new Get();
                  //   request.addHeader("Range", "bytes=" + frag.byterange_start_offset + "-" + frag.byterange_end_offset);
                  //   client.request(new URI(frag.url),request);
                  //}
              } catch (error:Error) {
                  _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, error.message));
              }
            }
        }


         /** Store the alternate audio track lists. **/
        private function _altAudioTracksListChangedHandler(event:HLSEvent):void {
         _altAudioTrackLists = event.altAudioTracks;
         Log.info(_altAudioTrackLists.length +  " alternate audio tracks found");
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event:HLSEvent):void {
            _levels = event.levels;
            _start_level = -1;
            _level = 0;
            _manifest_just_loaded = true;
            // reset audio tracks
            _audioTrackId = -1;
            _audioTracksfromDemux = new Vector.<HLSAudioTrack>();
            _audioTracksfromManifest = new Vector.<HLSAudioTrack>();
            _audioTracksMerge();
            // set up start level as being the lowest non-audio level.
            for(var i:Number = 0; i < _levels.length; i++) {
                if(!_levels[i].audio) {
                    _start_level = i;
                    break;
                }
            }
            // in case of audio only playlist, force startLevel to 0 
            if(_start_level == -1) {
               Log.info("playlist is audio-only");
               _start_level = 0;
            }
        };

         /** Store the manifest data. **/
         private function _levelUpdatedHandler(event:HLSEvent):void {
            _last_updated_level = event.level;
            if(_last_updated_level == _level) {
               var altAudioTrack:AltAudioTrack;
               var audioTrackList:Vector.<HLSAudioTrack> = new Vector.<HLSAudioTrack>(); 
               var stream_id:String = _levels[_level].audio_stream_id;
               // check if audio stream id is set, and alternate audio tracks available
               if(stream_id && _altAudioTrackLists) {
                  // try to find alternate audio streams matching with this ID
                  for( var idx:Number = 0 ; idx < _altAudioTrackLists.length ; idx++) {
                     altAudioTrack = _altAudioTrackLists[idx];
                     if(altAudioTrack.group_id == stream_id) {
                        var isDefault:Boolean = (altAudioTrack.default_track == true || altAudioTrack.autoselect == true);
                        Log.debug(" audio track[" + audioTrackList.length +"]:" + (isDefault ? "default:" : "alternate:") + altAudioTrack.name);
                        audioTrackList.push(new HLSAudioTrack(altAudioTrack.name, HLSAudioTrack.FROM_PLAYLIST, idx, isDefault));
                     }
                  }
               }
               // check if audio tracks matching with current level have changed since last time 
               var audio_track_changed:Boolean = false;
               if (_audioTracksfromManifest.length != audioTrackList.length) {
                  audio_track_changed = true;
               } else {
                  for (idx=0; idx<_audioTracksfromManifest.length; ++idx) {
                     if (_audioTracksfromManifest[idx].id != audioTrackList[idx].id) {
                        audio_track_changed = true;
                     }
                  }
               }
               // update audio list
               if (audio_track_changed) {
                  _audioTracksfromManifest = audioTrackList;
                  _audioTracksMerge();
               }
            }
         };

      // merge audio track info from demux and from manifest into a unified list that will be exposed to upper layer
    private function _audioTracksMerge():void {
      var i:Number;
      var default_demux:Number = -1;
      var default_manifest:Number = -1;
      var default_found:Boolean = false;
      var default_track_title:String;
      var audioTrack:HLSAudioTrack;
      _audioTracks = new Vector.<HLSAudioTrack>();
      
      // first look for default audio track.
      for (i=0;i<_audioTracksfromManifest.length;i++) {
         if(_audioTracksfromManifest[i].isDefault) {
            default_manifest = i;
            break;
         }
      }
      for (i=0;i<_audioTracksfromDemux.length;i++) {
         if(_audioTracksfromDemux[i].isDefault) {
            default_demux = i;
            break;
         }
      }
      /* default audio track from manifest should take precedence */
      if (default_manifest !=-1) {
         audioTrack = _audioTracksfromManifest[default_manifest];
         // if URL set, default audio track is not embedded into MPEG2-TS
         if(_altAudioTrackLists[audioTrack.id].url || default_demux ==-1) {
            Log.debug("default audio track found in Manifest");
            default_found = true;
            _audioTracks.push(audioTrack);
         } else { // empty URL, default audio track is embedded into MPEG2-TS. retrieve track title from manifest and override demux title
            default_track_title = audioTrack.title;
            if(default_demux != -1) {
               Log.debug("default audio track signaled in Manifest, will be retrieved from MPEG2-TS");
               audioTrack = _audioTracksfromDemux[default_demux];
               audioTrack.title = default_track_title;
               default_found = true;
               _audioTracks.push(audioTrack);
            }
         }
      } else if (default_demux !=-1 ){
         audioTrack = _audioTracksfromDemux[default_demux];
         default_found = true;
         _audioTracks.push(audioTrack);
      }
      // then append other audio tracks, start from manifest list, then continue with demux list
      for (i=0;i<_audioTracksfromManifest.length;i++) {
         if(!_audioTracksfromManifest[i].isDefault) {
            Log.debug("alternate audio track found in Manifest");
            audioTrack = _audioTracksfromManifest[i];
            _audioTracks.push(audioTrack);
         }
      }

      for (i=0;i<_audioTracksfromDemux.length;i++) {
         if(!_audioTracksfromDemux[i].isDefault) {
            Log.debug("alternate audio track retrieved from demux");
            audioTrack = _audioTracksfromDemux[i];
            _audioTracks.push(audioTrack);
         }
      }
      // notify audio track list update
      _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_TRACKS_LIST_CHANGE));

      // switch track id to default audio track, if found
      if(default_found == true && _audioTrackId ==-1) {
         setAudioTrack(0);
      }
    }

    /** Handles the actual reading of the TS fragment **/
    private function _fragReadHandler(audioTags:Vector.<Tag>,videoTags:Vector.<Tag>,adif:ByteArray,avcc:ByteArray,audioPID:Number=-1,audioTrackList:Vector.<HLSAudioTrack>=null):void {
       var audio_index:Number;
       var audio_track_changed:Boolean = false;
       audioTrackList = audioTrackList.sort(function(a:HLSAudioTrack,b:HLSAudioTrack):Number { return a.id - b.id; });
         for (var idx:int=0; idx<audioTrackList.length; ++idx) {
            // retrieve index id of current audio track
            if (audioTrackList[idx].id == audioPID) {
               audio_index = idx;
               break;
            }
         }
         if (_audioTracksfromDemux.length != audioTrackList.length) {
            audio_track_changed = true;
         } else {
            for (idx=0; idx<_audioTracksfromDemux.length; ++idx) {
               if (_audioTracksfromDemux[idx].id != audioTrackList[idx].id) {
                  audio_track_changed = true;
               }
            }
         }
         // update audio list if changed 
         if (audio_track_changed) {
            _audioTracksfromDemux = audioTrackList;
            _audioTracksMerge();
         }

       // Tags used for PTS analysis
       var min_pts:Number = Number.POSITIVE_INFINITY;
       var max_pts:Number = Number.NEGATIVE_INFINITY;
       var ptsTags:Vector.<Tag>;

      // reset IO error, as if we reach this point, it means fragment has been successfully retrieved and demuxed
      _bIOError = false;
      
      if(audioTags == null || videoTags == null) {
         var error_txt:String = "error parsing content";
         Log.error(error_txt);
         _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, error_txt));
      }

       if (audioTags.length > 0) {
        ptsTags = audioTags;
      } else {
      // no audio, video only stream
        ptsTags = videoTags;
      }

      for(var k:Number=0; k < ptsTags.length; k++) {
         min_pts = Math.min(min_pts,ptsTags[k].pts);
         max_pts = Math.max(max_pts,ptsTags[k].pts);
      }

      /* in case we are probing PTS, retrieve PTS info and synchronize playlist PTS / sequence number */
      if(_pts_loading_in_progress == true) {
        _levels[_level].updatePTS(_seqnum,min_pts,max_pts);
        Log.debug("analyzed  PTS " + _seqnum +  " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level "+ _level + " m/M PTS:" + min_pts +"/" + max_pts);
        /* check if fragment loaded for PTS analysis is the next one
            if this is the expected one, then continue and notify Buffer Manager with parsed content
            if not, then exit from here, this will force Buffer Manager to call loadnextfragment() and load the right seqnum
         */
        var next_seqnum:Number = _levels[_level].getSeqNumNearestPTS(_last_segment_start_pts,_last_segment_continuity_counter)+1;
        //Log.info("seq/next:"+ _seqnum+"/"+ next_seqnum);
        if (next_seqnum != _seqnum) {
          _pts_loading_in_progress = false;
          _pts_just_loaded = true;
          // tell that new fragment could be loaded
          _need_reload = true;
          return;
        }
      }

      var tags:Vector.<Tag> = new Vector.<Tag>();
      // Push codecprivate tags only when switching.
      if(_switchlevel) {
        if (videoTags.length > 0) {
          var avccTag:Tag = new Tag(Tag.AVC_HEADER,videoTags[0].pts,videoTags[0].dts,true);
          avccTag.push(avcc,0,avcc.length);
          tags.push(avccTag);
        }
        if (audioTags.length > 0) {
          if(audioTags[0].type == Tag.AAC_RAW) {
            var adifTag:Tag = new Tag(Tag.AAC_HEADER,audioTags[0].pts,audioTags[0].dts,true);
            adifTag.push(adif,0,2);
            tags.push(adifTag);
          }
        }
      }
      // Push regular tags into buffer.
      for(var i:Number=0; i < videoTags.length; i++) {
        tags.push(videoTags[i]);
      }
      for(var j:Number=0; j < audioTags.length; j++) {
        tags.push(audioTags[j]);
      }

      // change the media to null if the file is only audio.
      if(videoTags.length == 0) {
        _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_ONLY));
      }

      if (_cancel_load == true)
        return;

      // Calculate bandwidth
      _last_process_duration = (new Date().valueOf() - _frag_loading_start_time);
      _last_bandwidth = Math.round(_last_segment_size * 8000 / _last_process_duration);
      
      if(_manifest_just_loaded) {
         _manifest_just_loaded = false;
         if(startFromLowestLevel == false) {
            // check if we can directly switch to a better bitrate, in case download bandwidth is enough
            var bestlevel:Number = _autoLevelManager.getbestlevel(_last_bandwidth);
            if (bestlevel > _level) {
               Log.info("enough download bandwidth, adjust start level from "+ _level +  " to " + bestlevel);
               // let's directly jump to the accurate level to improve quality at player start
               _level = bestlevel;
               _need_reload = true;
               _switchlevel = true;
               _hls.dispatchEvent(new HLSEvent(HLSEvent.QUALITY_SWITCH,_level));
               return;
            }
         }
      }

      try {
         _switchlevel = false;
         _last_segment_duration = max_pts-min_pts;
         _last_segment_start_pts = min_pts;

         Log.debug("Loaded        " + _seqnum +  " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level "+ _level + " m/M PTS:" + min_pts +"/" + max_pts);
         var start_offset:Number = _levels[_level].updatePTS(_seqnum,min_pts,max_pts);
         _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED,_levels[_level].duration));
         _callback(tags,min_pts,max_pts,_hasDiscontinuity,start_offset);
         _pts_loading_in_progress = false;
         _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, getMetrics()));
      } catch (error:Error) {
        _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, error.toString()));
      }
    }


        /** Provide the loader with screen width information. **/
        public function setWidth(width:Number):void {
            _width = width;
        }

        /** return current quality level. **/
        public function get level():Number {
            return _level;
        };
        /* set current quality level */
        public function set level(level:Number):void {
           _manual_level = level;
        };

        /** get auto/manual level mode **/
        public function get autolevel():Boolean {
            if(_manual_level == -1) {
               return true;
            } else {
               return false;
            }
        };
    }
}