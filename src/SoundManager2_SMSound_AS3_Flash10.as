/*
   SoundManager 2: Javascript Sound for the Web
   ----------------------------------------------
   http://schillmania.com/projects/soundmanager2/

   Copyright (c) 2007, Scott Schiller. All rights reserved.
   Code licensed under the BSD License:
   http://www.schillmania.com/projects/soundmanager2/license.txt

   Flash 10 / ActionScript 3 version
*/

package {

  import flash.external.*;
  import flash.events.*;
  import flash.media.Sound;
  import flash.media.SoundChannel;
  import flash.media.SoundLoaderContext;
  import flash.media.SoundTransform;
  import flash.media.SoundMixer;
  import flash.net.URLRequest;
  import flash.utils.ByteArray;
  import flash.utils.getTimer;
  import flash.net.NetConnection;
  import flash.net.NetStream;

  public class SoundManager2_SMSound_AS3_Flash10 extends Sound {

    public var sm: SoundManager2_AS3_Flash10 = null;
    // externalInterface references (for Javascript callbacks)
    public var baseJSController: String = "soundManager";
    public var baseJSObject: String = baseJSController + ".sounds";
    public var soundChannel: SoundChannel = new SoundChannel();
    public var urlRequest: URLRequest;
    public var soundLoaderContext: SoundLoaderContext;
    public var waveformData: ByteArray = new ByteArray();
    public var waveformDataArray: Array = [];
    public var eqData: ByteArray = new ByteArray();
    public var eqDataArray: Array = [];
    public var usePeakData: Boolean = false;
    public var useWaveformData: Boolean = false;
    public var useEQData: Boolean = false;
    public var sID: String;
    public var sURL: String;
    public var justBeforeFinishOffset: int;
    public var didJustBeforeFinish: Boolean;
    public var didFinish: Boolean;
    public var loaded: Boolean;
    public var connected: Boolean;
    public var failed: Boolean;
    public var paused: Boolean;
    public var finished: Boolean;
    public var duration: Number;
    public var handledDataError: Boolean = false;
    public var ignoreDataError: Boolean = false;
    public var autoPlay: Boolean = false;
    public var autoLoad: Boolean = false;
    public var pauseOnBufferFull: Boolean = false; // only applies to RTMP
    public var loops: Number = 1;
    public var lastValues: Object = {
      bytes: 0,
      duration: 0,
      position: 0,
      volume: 100,
      pan: 0,
      panVolumeLeft: 1,
      panVolumeRight: 1,
      loops: 1,
      leftPeak: 0,
      rightPeak: 0,
      waveformDataArray: null,
      eqDataArray: null,
      isBuffering: null,
      bufferLength: 0
    };
    public var didLoad: Boolean = false;
    public var useEvents: Boolean = false;
    public var sound: Sound = new Sound();

    public var cc: Object;
    public var nc: NetConnection;
    public var ns: NetStream = null;
    public var st: SoundTransform;
    public var useNetstream: Boolean;
    public var bufferTime: Number = 3; // previously 0.1
    public var lastNetStatus: String = null;
    public var serverUrl: String = null;

    public var checkPolicyFile:Boolean = false;

    // FLASH 10 stuff

    public var block_size: int = 2048;

    public var _mp3: Sound = new Sound();
    public var _sound: Sound;
    public var _soundChannel: SoundChannel = null;

    public var _dynamicSoundPosition: Number = 0;

    public var dynamicSoundLatency: Number = 0;

    public var _target: ByteArray;

    public var _position: Number = 0.0;
    private var _rate: Number = 1.0;
    private var _absRate: Number = 1.0;

    public var leftEQ:EQ = new EQ();
    public var rightEQ:EQ = new EQ();

    public function enableEQ(): void {
      leftEQ.enabled = true;
      rightEQ.enabled = true;
    }

    public function disableEQ(): void {
      leftEQ.enabled = false;
      rightEQ.enabled = false;
    }

    public function setEQ(eqNumber:int, eqValue:Number): void {
      // update EQ values, and enable/disable accordingly
      if (leftEQ.gains[eqNumber]) {
        leftEQ.gains[eqNumber] = eqValue;
        rightEQ.gains[eqNumber] = eqValue;
        // if all are zero, disable the filter.
/*
        if (leftEQ.gains[0] === leftEQ.defaultGain && leftEQ.gains[1] === leftEQ.defaultGain && leftEQ.gains[2] === leftEQ.defaultGain) {
          writeDebug('disabling filter');
          leftEQ.enabled = false;
          rightEQ.enabled = false;
        } else {
          writeDebug('enabling filter');
          leftEQ.enabled = true;
          rightEQ.enabled = true;
        }
*/
      }
    }

    public function startDynamicSound(): void {
      if (_soundChannel === null) {
        _sound.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        _soundChannel = _sound.play();
      } else {
        writeDebug('startDynamicSound(): channel already active?');	
      }
    }

    public function setBlockSize(blockSize:int):void {
      // kinda/sorta compensate for difference in block size
      var didStop:Boolean = false;
      if (blockSize < block_size) {
        // over record
        _position -= ((block_size - blockSize)*8);
        _position += blockSize*4;
      } else {
        // leaving record
        _position += block_size;
      }
      block_size = blockSize;
      if (_sound) {
        if (_soundChannel) {
          _soundChannel.stop();
          _soundChannel = null;
          didStop = true;
        }
        _sound.removeEventListener(SampleDataEvent.SAMPLE_DATA, sampleData);
        // writeDebug('removing/re-assigning sample data event');
        _sound.addEventListener(SampleDataEvent.SAMPLE_DATA, sampleData);
        if (didStop) {
          startDynamicSound();
        }
      }
    }

    public function setRate(value:Number):void {
      // called from JS
      _rate = value;
      _absRate = Math.abs(value);
    }

    public function stopDynamicSound(): void {
      writeDebug('stopDynamicSound()');
      if (_soundChannel) {
        writeDebug('stopDynamicSound(): Stopping channel...');
        _soundChannel.stop();
        _soundChannel = null;
      } else {
        writeDebug('stopDynamicSound(): No channel to stop.');
      }
    }

    public function getDynamicSoundLatency(): Number {
      return dynamicSoundLatency;
    }

    private function sampleData( event: SampleDataEvent ): void {

      /*
       * Many thanks to Kelvin Luck and Andre Michelle for their code examples and research.
       * Without their resources, I don't think I would have been able to make this work at all. ;)
       * http://www.kelvinluck.com/2009/03/second-steps-with-flash-10-audio-programming/
       * http://blog.andre-michelle.com/2009/pitch-mp3/
      */

      _target.position = 0;

      var data: ByteArray = event.data;

      var blockSize: int = block_size; // store locally, for this loop

      var scaledBlockSize: Number = blockSize * _absRate;
      var positionInt: int = _position;
      var alpha: Number = _position - positionInt;
      var positionTargetNum: Number = alpha;
      var positionTargetInt: int = -1;

      // # of samples needed (+2 for interpolation)
      var need: int = Math.ceil( scaledBlockSize ) + 2;

      var read: int;
      var readPosition: int;

      if (_rate < 0) {

        if (need < blockSize) {
          // HACK: For cases where _rate is from -1 to 0.
          need = blockSize + 2; // ...including interpolation
        }

        if (positionInt >= 0) {

          // limit readPosition to 0, if reading backward.
          readPosition = (need > positionInt ? 0 : positionInt - need);

          read = _mp3.extract(_target, need, readPosition);

        }

        // add empty samples if we didn't get enough data (ie., read back to beginning of sound.)
        while (need > read) {
          _target.writeFloat(0.0);
          _target.writeFloat(0.0);
          ++read; // # of bytes per float
        }

      } else {

          // read forward.
          readPosition = positionInt;
          read = _mp3.extract( _target, need, positionInt);

      }

      /*
      if (positionInt < 0) {
        writeDebug('writing zeroes');
        // just write empty zeroes.
        _target.position = 0;
        for (var x:int = 0; x < need; x++) {
          _target.writeFloat(0.0);
        }
        // need = read;
        read = need;
      }
      */

      var n: int = read == need ? blockSize : read / _absRate;

      if (positionInt < 0) {
        // don't do anything.
        n = 0;
      }

      /*
      if (_rate < -1) {
        // playing backwards
        n = read / _absRate; // ?
      }
      */

      var l0: Number = 0.0;
      var r0: Number = 0.0;
      var l1: Number = 0.0;
      var r1: Number = 0.0;

      var position_offset:int;

      var volume: Number = this.lastValues.volume;
      var duration: Number = this.length; // actual sound object value

      var eqEnabled:Boolean = leftEQ.enabled;

      for (var i: int = 0 ; i < n ; ++i) {

        // don't read equal samples if rate is < 1.0

        if (int(positionTargetNum) != positionTargetInt) {

          positionTargetInt = positionTargetNum;

          // set target read position

          if (_rate >= 0) {

            position_offset = (positionTargetInt << 3);

          } else {

            if (_rate < -1) {

              // "end of file", scaled up, minus current (forward-moving loop) value
              position_offset = ((n*_absRate << 3) - ((positionTargetInt << 3))); // and counter for the rate being < -1.

            } else {

              // "end of file" minus current loop
              position_offset = ((n << 3) - (positionTargetInt << 3));

            }

          }

          _target.position = position_offset;

          // don't ever output this unless you're really stuck in debugging and want to kill CPU, etc. :D
          // writeDebug('At '+i+': Reading from '+(n << 3)+'-'+(positionTargetInt << 3)+' = '+position_offset +'(applied: '+_target.position+'), writing to '+data.position);

          // read two stereo samples for linear interpolation

          l0 = _target.readFloat();
          r0 = _target.readFloat();

          l1 = _target.readFloat();
          r1 = _target.readFloat();

        }

        // write interpolated values into stream

        if (eqEnabled) {

          data.writeFloat( leftEQ.compute(l0 + alpha * ( l1 - l0 )) * volume );
          data.writeFloat( rightEQ.compute(r0 + alpha * ( r1 - r0 )) * volume );

        } else {

          data.writeFloat( (l0 + alpha * ( l1 - l0 )) * volume );
          data.writeFloat( (r0 + alpha * ( r1 - r0 )) * volume );

        }

        // move to new position in data source
        positionTargetNum += _absRate;

        // increase fraction and clamp between 0 and 1
        alpha += _rate;

        if (_rate >= 0) {

          while (alpha >= 1.0) {
            --alpha;
          }

        } else {

          while (alpha <= -1.0) {
            ++alpha;
          }

        }

      }

      // pad remainder with silence

      if (i < blockSize) {
        // writeDebug('writing '+(blockSize-i)+' zeroes');
        while (i < blockSize) {
          data.writeFloat( 0.0 );
          data.writeFloat( 0.0 );
          ++i;
        }
      }

      // increase sound position

      if (_rate >= 0) {
        _position += scaledBlockSize;
      } else {
        _position -= scaledBlockSize;
        if (_position < -8192) {
          // TODO: Allow silence.
          _position = -8192;
        }
      }

      // limit checks - don't go past the actual end of the song, eh?

      if (_position/44.1 > duration) {

        _position = duration*44.1;
        // we should fire oncomplete/onfinish now.
        if (!this.finished) {
          this.finished = true;
          writeDebug('calling onfinish for sound '+this.sID);
          this.sm.checkProgress();
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
        }

      } else if (this.finished) {

        // reset, allow onfinish() to fire again if user repositioned sound, etc.
        this.finished = false;

      }

      _dynamicSoundPosition = (_position/44.1); // where we actually are in the real sound.

      // http://help.adobe.com/en_US/as3/dev/WSE523B839-C626-4983-B9C0-07CF1A087ED7.html
      dynamicSoundLatency = (event.position && _soundChannel && _soundChannel.position ? (event.position / 44.1) - _soundChannel.position : 0);

      // writeDebug('position: '+_dyamicSoundPosition);

    }

    public function SoundManager2_SMSound_AS3_Flash10(oSoundManager: SoundManager2_AS3_Flash10, sIDArg: String = null, sURLArg: String = null, usePeakData: Boolean = false, useWaveformData: Boolean = false, useEQData: Boolean = false, useNetstreamArg: Boolean = false, netStreamBufferTime: Number = 1, serverUrl: String = null, duration: Number = 0, autoPlay: Boolean = false, useEvents: Boolean = false, autoLoad: Boolean = false, checkPolicyFile: Boolean = false) {
      this.sm = oSoundManager;
      this.sID = sIDArg;
      this.sURL = sURLArg;
      this.usePeakData = usePeakData;
      this.useWaveformData = useWaveformData;
      this.useEQData = useEQData;
      this.urlRequest = new URLRequest(sURLArg);
      this.justBeforeFinishOffset = 0;
      this.didJustBeforeFinish = false;
      this.didFinish = false; // non-MP3 formats only
      this.loaded = false;
      this.connected = false;
      this.failed = false;
      this.finished = false;
      this.soundChannel = null;
      this.lastNetStatus = null;
      this.useNetstream = useNetstreamArg;
      this.serverUrl = serverUrl;
      this.duration = duration;
      this.useEvents = useEvents;
      this.autoLoad = autoLoad;
      if (netStreamBufferTime) {
        this.bufferTime = netStreamBufferTime;
      }
      this.checkPolicyFile = checkPolicyFile;

      writeDebug('SoundManager2_SMSound_AS3_Flash10: Got duration: '+duration+', autoPlay: '+autoPlay);

      if (this.useNetstream) {
        // Pause on buffer full if auto-loading an RTMP stream
        if (this.serverUrl && this.autoLoad) {
          this.pauseOnBufferFull = true;
        }

        this.cc = new Object();
        this.nc = new NetConnection();

        // Handle FMS bandwidth check callback.
        // @see onBWDone
        // @see http://www.adobe.com/devnet/flashmediaserver/articles/dynamic_stream_switching_04.html
        // @see http://www.johncblandii.com/index.php/2007/12/fms-a-quick-fix-for-missing-onbwdone-onfcsubscribe-etc.html
        this.nc.client = this;

        // TODO: security/IO error handling
        // this.nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR, doSecurityError);
        nc.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);

        if (this.serverUrl != null) {
          writeDebug('SoundManager2_SMSound_AS3_Flash10: NetConnection: connecting to server ' + this.serverUrl + '...');
        }
        this.nc.connect(serverUrl);
      } else {
        this.connected = true;
      }

    }

    public function netStatusHandler(event:NetStatusEvent):void {

      if (this.useEvents) {
        writeDebug('netStatusHandler: '+event.info.code);
      }

      switch (event.info.code) {

        case "NetConnection.Connect.Success":
          writeDebug('NetConnection: connected');
          try {
            this.ns = new NetStream(this.nc);
            this.ns.checkPolicyFile = this.checkPolicyFile;
            // bufferTime reference: http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/net/NetStream.html#bufferTime
            this.ns.bufferTime = this.bufferTime; // set to 0.1 or higher. 0 is reported to cause playback issues with static files.
            this.st = new SoundTransform();
            this.cc.onMetaData = this.metaDataHandler;
            this.ns.client = this.cc;
            this.ns.receiveAudio(true);
            this.addNetstreamEvents();
            this.connected = true;
            if (this.useEvents) {
              writeDebug('firing _onconnect for '+this.sID);
              ExternalInterface.call(this.sm.baseJSObject + "['" + this.sID + "']._onconnect", 1);
            }
          } catch(e: Error) {
            this.failed = true;
            writeDebug('netStream error: ' + e.toString());
            ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection failed!', event.info.level, event.info.code);
          }
          break;

        case "NetStream.Play.StreamNotFound":
          this.failed = true;
          writeDebug("NetConnection: Stream not found!");
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Stream not found!', event.info.level, event.info.code);
          break;

        // This is triggered when the sound loses the connection with the server.
        // In some cases one could just try to reconnect to the server and resume playback.
        // However for streams protected by expiring tokens, I don't think that will work.
        //
        // Flash says that this is not an error code, but a status code...
        // should this call the onFailure handler?
        case "NetConnection.Connect.Closed":
          this.failed = true;
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection closed!', event.info.level, event.info.code);
          writeDebug("NetConnection: Connection closed!");
          break;

        // Couldn't establish a connection with the server. Attempts to connect to the server
        // can also fail if the permissible number of socket connections on either the client
        // or the server computer is at its limit.  This also happens when the internet
        // connection is lost.
        case "NetConnection.Connect.Failed":
          this.failed = true;
          writeDebug("NetConnection: Connection failed! Lost internet connection? Try again... Description: " + event.info.description);
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection failed!', event.info.level, event.info.code);
          break;

        // A change has occurred to the network status. This could mean that the network
        // connection is back, or it could mean that it has been lost...just try to resume
        // playback.

        // KJV: Can't use this yet because by the time you get your connection back the
        // song has reached it's maximum retries, so it doesn't retry again.  We need
        // a new _ondisconnect handler.
        //case "NetConnection.Connect.NetworkChange":
        //  this.failed = true;
        //  writeDebug("NetConnection: Network connection status changed");
        //  ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Reconnecting...');
        //  break;

        // Consider everything else a failure...
        default:
          this.failed = true;
          writeDebug("NetConnection: got unhandled code '" + event.info.code + "'! Description: " + event.info.description);
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", '', event.info.level, event.info.code);
          break;
      }

    }

    public function writeDebug (s: String, bTimestamp: Boolean = false) : Boolean {
      return this.sm.writeDebug (s, bTimestamp); // defined in main SM object
    }

    public function metaDataHandler(infoObject: Object) : void {
      if (sm.debugEnabled) {
        var data:String = new String();
        for (var prop:* in infoObject) {
          data += prop+': '+infoObject[prop]+' \n';
        }
        writeDebug('Metadata: '+data);
      }
      this.duration = infoObject.duration * 1000;
      if (!this.loaded) {
        // writeDebug('not loaded yet: '+this.ns.bytesLoaded+', '+this.ns.bytesTotal+', '+infoObject.duration*1000);
        // TODO: investigate loaded/total values
        // ExternalInterface.call(baseJSObject + "['" + this.sID + "']._whileloading", this.ns.bytesLoaded, this.ns.bytesTotal, infoObject.duration*1000);
        ExternalInterface.call(baseJSObject + "['" + this.sID + "']._whileloading", this.bytesLoaded, this.bytesTotal, (infoObject.duration || this.duration))
      }
      // null this out for the duration of this object's existence.
      // it may be called multiple times.
      this.cc.onMetaData = function(infoObject: Object) : void {}

    }

    public function getWaveformData() : void {
      // http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
      SoundMixer.computeSpectrum(this.waveformData, false, 0); // sample wave data at 44.1 KHz
      this.waveformDataArray = [];
      for (var i: int = 0, j: int = this.waveformData.length / 4; i < j; i++) { // get all 512 values (256 per channel)
        this.waveformDataArray.push(int(this.waveformData.readFloat() * 1000) / 1000);
      }
    }

    public function getEQData() : void {
      // http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
      SoundMixer.computeSpectrum(this.eqData, true, 0); // sample EQ data at 44.1 KHz
      this.eqDataArray = [];
      for (var i: int = 0, j: int = this.eqData.length / 4; i < j; i++) { // get all 512 values (256 per channel)
        this.eqDataArray.push(int(this.eqData.readFloat() * 1000) / 1000);
      }
    }

    public function start(nMsecOffset: int, nLoops: int) : void {
      this.useEvents = true;
      if (this.useNetstream) {

        writeDebug("SMSound::start nMsecOffset "+ nMsecOffset+ ' nLoops '+nLoops + ' current bufferTime '+this.ns.bufferTime+' current bufferLength '+this.ns.bufferLength+ ' this.lastValues.position '+this.lastValues.position);

        this.cc.onMetaData = this.metaDataHandler;

        // Don't seek if we don't have to because it destroys the buffer
        var set_position:Boolean = this.lastValues.position != null && this.lastValues.position != nMsecOffset;
        if (set_position) {
          // Minimize the buffer so playback starts ASAP
          this.ns.bufferTime = this.bufferTime;
        }

        if (this.paused) {
          writeDebug('start: resuming from paused state');
          this.ns.resume(); // get the sound going again
          if (!this.didLoad) {
            this.didLoad = true;
          }
          this.paused = false;
        } else if (!this.didLoad) {
          writeDebug('start: !didLoad - playing '+this.sURL);
          this.ns.play(this.sURL);
          this.pauseOnBufferFull = false; // SAS: playing behaviour overrides buffering behaviour
          this.didLoad = true;
          this.paused = false;
        } else {
          // previously loaded, perhaps stopped/finished. play again?
          writeDebug('playing again (not paused, didLoad = true)');
          this.pauseOnBufferFull = false;
          this.ns.play(this.sURL);
        }

        // KJV seek after calling play otherwise some streams get a NetStream.Seek.Failed
        // Should only apply to the !didLoad case, but do it for all for simplicity.
        // nMsecOffset is in milliseconds for streams but in seconds for progressive
        // download.
        if (set_position) {
          this.ns.seek(this.serverUrl ? nMsecOffset / 1000 : nMsecOffset);
          this.lastValues.position = nMsecOffset; // https://gist.github.com/1de8a3113cf33d0cff67
        }

        // this.ns.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();

      } else {
        // writeDebug('start: seeking to '+nMsecOffset+', '+nLoops+(nLoops==1?' loop':' loops'));
        this.soundChannel = this.play(nMsecOffset, nLoops);
        // this.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();
      }

    }

    private function _onfinish() : void {
      _sound.removeEventListener(Event.SOUND_COMPLETE, _onfinish);
    }

    public function loadSound(sURL: String) : void {
      if (this.useNetstream) {
        this.useEvents = true;
        if (this.didLoad != true) {
          this.ns.play(this.sURL); // load streams by playing them
          if (!this.autoPlay) {
            this.pauseOnBufferFull = true;
          }
          this.paused = false;
        }
        // this.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();
      } else {
        try {
          this.didLoad = true;
          this.urlRequest = new URLRequest(sURL);
          this.soundLoaderContext = new SoundLoaderContext(1000, this.checkPolicyFile); // check for policy (crossdomain.xml) file on remote domains - http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundLoaderContext.html
          this.load(this.urlRequest, this.soundLoaderContext);

          stopDynamicSound();

          writeDebug('Creating and loading _mp3...');
          _target = new ByteArray();
          _mp3 = new Sound();
          // _mp3.addEventListener( Event.COMPLETE, startDynamicSound );
          _mp3.load(this.urlRequest, this.soundLoaderContext);

          if (_sound) {
            _sound.removeEventListener( SampleDataEvent.SAMPLE_DATA, sampleData );
          }

          writeDebug('Creating _sound...');
          _sound = new Sound();
          _sound.addEventListener( SampleDataEvent.SAMPLE_DATA, sampleData );

      writeDebug('adding event.COMPLETE for dynamic sound...');
      // this.addEventListener( Event.COMPLETE, complete );


        } catch(e: Error) {
          writeDebug('error during loadSound(): ' + e.toString());
        }
      }
    }

    // Set the value of autoPlay
    public function setAutoPlay(autoPlay: Boolean) : void {
      if (!this.serverUrl) {
        this.autoPlay = autoPlay;
      } else {
        this.autoPlay = autoPlay;
        if (this.autoPlay) {
          this.pauseOnBufferFull = false;
        } else if (!this.autoPlay) {
          this.pauseOnBufferFull = true;
        }
      }
    }

    public function setVolume(nVolume: Number) : void {
      // writeDebug('setVolume: '+nVolume);
      this.lastValues.volume = nVolume / 100;
      this.applyTransform();
      // writeDebug('setVolume, end value: '+this.lastValues.volume);
    }

    public function setPan(nPan: Number) : void {
      this.lastValues.pan = nPan / 100;

      // 0 = left 100% / 50 = 0% left/right / 100% = right 100%
      /*
      var leftVolume:Number;
      var rightVolume:Number;

      if (nPan > 50) {
        leftVolume = 1 - (1 * (nPan-50)/50);
        rightVolume = 1;
      } else if (nPan === 50) {
        leftVolume = 1;
        rightVolume = 1;
      } else {
        leftVolume = 1;
        rightVolume = 1 * nPan/50;
      }

      this.lastValues.panVolumeLeft = leftVolume;
      this.lastValues.panVolumeRight = rightVolume;

      writeDebug('pan: '+this.lastValues.panVolumeLeft+', '+this.lastValues.panVolumeRight);
      */

      this.applyTransform();
    }

    public function applyTransform() : void {
      var st: SoundTransform = new SoundTransform(this.lastValues.volume, this.lastValues.pan);
      if (this.useNetstream) {
        if (this.ns) {
          this.ns.soundTransform = st;
        } else {
          // writeDebug('applyTransform(): Note: No active netStream');
        }
      } else if (this.soundChannel) {
        this.soundChannel.soundTransform = st; // new SoundTransform(this.lastValues.volume, this.lastValues.pan);
        var st2: SoundTransform = new SoundTransform(0, this.lastValues.pan);
        // actually, mute the original sound at all times.
        this.soundChannel.soundTransform = st2;
      }
    }

    // Handle FMS bandwidth check callback.
    // @see http://www.adobe.com/devnet/flashmediaserver/articles/dynamic_stream_switching_04.html
    // @see http://www.johncblandii.com/index.php/2007/12/fms-a-quick-fix-for-missing-onbwdone-onfcsubscribe-etc.html
    public function onBWDone() : void {
      // writeDebug('onBWDone: called and ignored');
    }

    // NetStream client callback. Invoked when the song is complete.
    public function onPlayStatus(info:Object):void {
      writeDebug('onPlayStatus called with '+info);
      switch(info.code) {
        case "NetStream.Play.Complete":
          writeDebug('Song has finished!');
          break;
      }
    }

    public function doIOError(e: IOErrorEvent) : void {
      ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onload", 0); // call onload, assume it failed.
      // there was a connection drop, a loss of internet connection, or something else wrong. 404 error too.
    }

    public function doAsyncError(e: AsyncErrorEvent) : void {
      writeDebug('asyncError: ' + e.text);
    }

    public function doNetStatus(e: NetStatusEvent) : void {

      // Handle failures
      if (e.info.code == "NetStream.Failed"
          || e.info.code == "NetStream.Play.FileStructureInvalid"
          || e.info.code == "NetStream.Play.StreamNotFound") {

        this.lastNetStatus = e.info.code;
        writeDebug('netStatusEvent: ' + e.info.code);
        this.failed = true;
        ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", '', e.info.level, e.info.code);
        return;
      }

      writeDebug('netStatusEvent: ' + e.info.code);  // KJV we like to see all events

      // When streaming, Stop is called when buffering stops, not when the stream is actually finished.
      // @see http://www.actionscript.org/forums/archive/index.php3/t-159194.html
      if (e.info.code == "NetStream.Play.Stop") {

        if (!this.useNetstream) {
          // finished playing
          // this.didFinish = true; // will be reset via JS callback
          this.didJustBeforeFinish = false; // reset
          writeDebug('calling onfinish for a sound');
          // reset the sound? Move back to position 0?
          this.sm.checkProgress();
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
        }

      } else if (e.info.code == "NetStream.Play.Start" || e.info.code == "NetStream.Buffer.Empty" || e.info.code == "NetStream.Buffer.Full") {

        // RTMP case..
        // We wait for the buffer to fill up before pausing the just-loaded song because only if the
        // buffer is full will the song continue to buffer until the user hits play.
        if (this.serverUrl && e.info.code == "NetStream.Buffer.Full" && this.pauseOnBufferFull) {
          this.ns.pause();
          this.paused = true;
          this.pauseOnBufferFull = false;
          // Call pause in JS.  This will call back to us to pause again, but
          // that should be harmless.
          writeDebug('Pausing on buffer full');
          ExternalInterface.call(baseJSObject + "['" + this.sID + "'].pause", false);
        }

        var isNetstreamBuffering: Boolean = (e.info.code == "NetStream.Buffer.Empty" || e.info.code == "NetStream.Play.Start");
        // assume buffering when we start playing, eg. initial load.
        if (isNetstreamBuffering != this.lastValues.isBuffering) {
          this.lastValues.isBuffering = isNetstreamBuffering;
          ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onbufferchange", this.lastValues.isBuffering ? 1 : 0);
        }

        // We can detect the end of the stream when Play.Stop is called followed by Buffer.Empty.
        // However, if you pause and let the whole song buffer, Buffer.Flush is called followed by
        // Buffer.Empty, so handle that case too.
        //
        // Ignore this event if we are more than 5 seconds from the end of the song.
        if (e.info.code == "NetStream.Buffer.Empty" && (this.lastNetStatus == 'NetStream.Play.Stop' || this.lastNetStatus == 'NetStream.Buffer.Flush')) {
          if (this.duration && (this.ns.time * 1000) < (this.duration - 5000)) {
            writeDebug('Ignoring Buffer.Empty because this is too early to be the end of the stream! (sID: '+this.sID+', time: '+(this.ns.time*1000)+', duration: '+this.duration+')');
          } else {
            this.didJustBeforeFinish = false; // reset
            this.finished = true;
            writeDebug('calling onfinish for sound '+this.sID);
            this.sm.checkProgress();
            ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
          }

        } else if (e.info.code == "NetStream.Buffer.Empty") {
          // The buffer is empty.  Start from the smallest buffer again.
          this.ns.bufferTime = this.bufferTime;
        }
      }

      // Remember the last NetStatus event
      this.lastNetStatus = e.info.code;
    }

    // KJV The sound adds some of its own netstatus handlers so we don't need to do it here.
    public function addNetstreamEvents() : void {
      ns.addEventListener(AsyncErrorEvent.ASYNC_ERROR, doAsyncError);
      ns.addEventListener(NetStatusEvent.NET_STATUS, doNetStatus);
      ns.addEventListener(IOErrorEvent.IO_ERROR, doIOError);
    }

    public function removeNetstreamEvents() : void {
      ns.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, doAsyncError);
      ns.removeEventListener(NetStatusEvent.NET_STATUS, doNetStatus);
      ns.addEventListener(NetStatusEvent.NET_STATUS, dummyNetStatusHandler);
      ns.removeEventListener(IOErrorEvent.IO_ERROR, doIOError);
      // KJV Stop listening for NetConnection events on the sound
      nc.removeEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
    }

    // Prevents possible 'Unhandled NetStatusEvent' condition if a sound is being
    // destroyed and interacted with at the same time.
    public function dummyNetStatusHandler(e: NetStatusEvent) : void {
      // Don't do anything
    }
  }
}