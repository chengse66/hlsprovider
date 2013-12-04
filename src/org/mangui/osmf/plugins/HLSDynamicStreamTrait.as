package org.mangui.osmf.plugins
{
  import org.osmf.traits.DynamicStreamTrait;
  import org.osmf.utils.OSMFStrings;
  import org.mangui.HLS.HLS;
  import org.mangui.HLS.HLSEvent;
  import org.mangui.HLS.utils.*;

  public class HLSDynamicStreamTrait extends DynamicStreamTrait
  {
    private var _hls:HLS;
    private var currentLevel:Number;
    public function HLSDynamicStreamTrait(hls:HLS)
    {
      _hls = hls;
      _hls.addEventListener(HLSEvent.QUALITY_SWITCH,_qualitySwitchHandler);
      super(true,0,hls.getLevels().length);
    }
   

    override public function getBitrateForIndex(index:int):Number
    {
      if (index > numDynamicStreams - 1 || index < 0)
      {
        throw new RangeError(OSMFStrings.getString(OSMFStrings.STREAMSWITCH_INVALID_INDEX));
      }
      var bitrate:Number = _hls.getLevels[index].bitrate/1024;
      Log.txt("HLSDynamicStreamTrait:getBitrateForIndex("+index+")="+bitrate);
      return bitrate;
    }


    override public function switchTo(index:int):void
    {
      Log.txt("HLSDynamicStreamTrait:switchTo("+index+")/max:"+maxAllowedIndex);
      if (index < 0 || index > maxAllowedIndex)
      {
        throw new RangeError(OSMFStrings.getString(OSMFStrings.STREAMSWITCH_INVALID_INDEX));
      }
      autoSwitch = false;
      if (!switching)
      {
        setSwitching(true, index);
      }
    }

    override protected function autoSwitchChangeStart(value:Boolean):void
    {
      Log.txt("HLSDynamicStreamTrait:autoSwitchChangeStart:"+value);
      if(value == true) {
        _hls.setPlaybackQuality(-1);
      }
    }

    override protected function switchingChangeStart(newSwitching:Boolean, index:int):void
    {
      Log.txt("HLSDynamicStreamTrait:switchingChangeStart(newSwitching/index):"+newSwitching + "/" + index);
      if(newSwitching) {
        _hls.setPlaybackQuality(index);
      }
    }

    /** Update playback position/duration **/
    private function _qualitySwitchHandler(event:HLSEvent):void {
      var newLevel:Number = event.level;
      Log.txt("HLSDynamicStreamTrait:_qualitySwitchHandler:"+newLevel);
      setCurrentIndex(newLevel);
      setSwitching(false, newLevel);
    };
  }
}