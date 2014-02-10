package org.mangui.flowplayer {

   import flash.display.DisplayObject;
   import flash.net.NetConnection;
   import flash.net.NetStream;
   import flash.utils.Dictionary;
  
   import org.mangui.HLS.utils.Log;

   import org.flowplayer.model.Plugin;
   import org.flowplayer.model.PluginModel;
   import org.flowplayer.view.Flowplayer;
   import org.flowplayer.controller.StreamProvider;
   import org.flowplayer.controller.TimeProvider;
   import org.flowplayer.controller.VolumeController;
   import org.flowplayer.model.ClipEvent;
   import org.flowplayer.model.Clip;
   import org.flowplayer.model.Playlist;

   public class HLSProvider  implements StreamProvider,Plugin {
      
         private var _volumecontroller:VolumeController;
         private var _playlist:Playlist;
         private var _timeProvider:TimeProvider;

        private var _model:PluginModel;
        private var _player:Flowplayer;
        
      public function getDefaultConfig():Object {
            return null;
        }
      
        public function onConfig(model:PluginModel):void {
             Log.info("onConfig()");
            _model = model;
        }
    
        public function onLoad(player:Flowplayer):void {
            Log.info("onLoad()");
            _player = player;
            _model.dispatchOnLoad();
        }

        /**
         * Starts loading the specivied clip. Once video data is available the provider
         * must set it to the clip using <code>clip.setContent()</code>. Typically the video
         * object passed to the clip is an instance of <a href="http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/Video.html">flash.media.Video</a>.
         *
         * @param event the event that this provider should dispatch once loading has successfully started,
         * once dispatched the player will call <code>getVideo()</code>
         * @param clip the clip to load
         * @param pauseAfterStart if <code>true</code> the playback is paused on first frame and
         * buffering is continued
         * @see Clip#setContent()
         * @see #getVideo()
         */
        public function load(event:ClipEvent, clip:Clip, pauseAfterStart:Boolean = true):void {
            Log.info("load()" + clip.completeUrl);
            return;
        }

        /**
         * Gets the <a href="http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/Video.html">Video</a> object.
         * A stream will be attached to the returned video object using <code>attachStream()</code>.
         * @param clip the clip for which the Video object is queried for
         * @see #attachStream()
         */
        public function getVideo(clip:Clip):DisplayObject {
         Log.info("getVideo()");
         return null;
        }

        /**
         * Attaches a stream to the specified display object.
         * @param video the video object that was originally retrieved using <code>getVideo()</code>.
         * @see #getVideo()
         */
        public function attachStream(video:DisplayObject):void {
            Log.info("attachStream()");
            return;
        }

        /**
         * Pauses playback.
         * @param event the event that this provider should dispatch once loading has been successfully paused
         */
        public function pause(event:ClipEvent):void {
            Log.info("pause()");
            return;
        }

        /**
         * Resumes playback.
         * @param event the event that this provider should dispatch once loading has been successfully resumed
         */
        public function resume(event:ClipEvent):void {
            Log.info("resume()");
            return;
        }

        /**
         * Stops and rewinds to the beginning of current clip.
         * @param event the event that this provider should dispatch once loading has been successfully stopped
         */
        public function stop(event:ClipEvent, closeStream:Boolean = false):void {
            Log.info("stop()");
            return;
        }

        /**
         * Seeks to the specified point in the timeline.
         * @param event the event that this provider should dispatch once the seek is in target
         * @param seconds the target point in the timeline
         */
        public function seek(event:ClipEvent, seconds:Number):void {
            Log.info("seek()");
            return;
        }

        /**
         * File size in bytes.
         */
        public function get fileSize():Number {
            return 0;
        }

        /**
         * Current playhead time in seconds.
         */
        public function get time():Number {
            return 0;
        }

        /**
         * The point in timeline where the buffered data region begins, in seconds.
         */
        public function get bufferStart():Number {
            return 0;
        }

        /**
         * The point in timeline where the buffered data region ends, in seconds.
         */
        public function get bufferEnd():Number {
            return 0;
        }

        /**
         * Does this provider support random seeking to unbuffered areas in the timeline?
         */
        public function get allowRandomSeek():Boolean {
            Log.debug("allowRandomSeek()");
            return true;
        }

        /**
         * Volume controller used to control the video volume.
         */
         
        public function set volumeController(controller:VolumeController):void {
            _volumecontroller = controller;
            return;
        }

        /**
         * Is this provider in the process of stopping the stream?
         * When stopped the provider should not dispatch any events resulting from events that
         * might get triggered by the underlying streaming implementation.
         */
        public function get stopping():Boolean {
            Log.info("stopping()");
            return false;
        }

        /**
         * The playlist instance.
         */
        public function set playlist(playlist:Playlist):void {
            Log.debug("set playlist()");
            _playlist = playlist;
            return;
        }

        public function get playlist():Playlist {
            Log.debug("get playlist()");
            return _playlist;
        }
        

        /**
         * Adds a callback public function to the NetConnection instance. This public function will fire ClipEvents whenever
         * the callback is invoked in the connection.
         * @param name
         * @param listener
         * @return
         * @see ClipEventType#CONNECTION_EVENT
         */
        public function addConnectionCallback(name:String, listener:Function):void {
            Log.info("addConnectionCallback()");
            return;
        }

        /**
         * Adds a callback public function to the NetStream object. This public function will fire a ClipEvent of type StreamEvent whenever
         * the callback has been invoked on the stream. The invokations typically come from a server-side app running
         * on RTMP server.
         * @param name
         * @param listener
         * @return
         * @see ClipEventType.NETSTREAM_EVENT
         */
        public function addStreamCallback(name:String, listener:Function):void {
            Log.info("addStreamCallback()");
            return;
        }

        /**
         * Get the current stream callbacks.
         * @return a dictionary of callbacks, keyed using callback names and values being the callback functions
         */
        public function get streamCallbacks():Dictionary {
            Log.info("get streamCallbacks()");
            return null;
        }

        /**
         * Gets the underlying NetStream object.
         * @return the netStream currently in use, or null if this provider has not started streaming yet
         */
        public function get netStream():NetStream {
            Log.info("get netStream()");
            return null;
        }

        /**
         * Gets the underlying netConnection object.
         * @return the netConnection currently in use, or null if this provider has not started streaming yet
         */
        public function get netConnection():NetConnection {
            Log.info("get netConnection()");
            return null;
        }


        /**
         * Sets a time provider to be used by this StreamProvider. Normally the playhead time is queried from
         * the NetStream.time property.
         *
         * @param timeProvider
         */
        public function set timeProvider(timeProvider:TimeProvider):void {
            Log.debug("set timeProvider()");
            _timeProvider = timeProvider;
            return;
        }

        /**
         * Gets the type of StreamProvider either http, rtmp, psuedo.
         */
        public function get type():String {
         return "httpstreaming";
        }

        /**
         * Switch the stream in realtime with / without dynamic stream switching support
         *
         * @param event ClipEvent the clip event
         * @param clip Clip the clip to switch to
         * @param netStreamPlayOptions Object the NetStreamPlayOptions object to enable dynamic stream switching
         */
        public function switchStream(event:ClipEvent, clip:Clip, netStreamPlayOptions:Object = null):void {
            Log.info("switchStream()");
            return;
        }
    
   }
}
