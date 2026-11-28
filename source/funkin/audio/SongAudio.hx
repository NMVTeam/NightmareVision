package funkin.audio;

import haxe.Timer;
import openfl.media.Sound;
import flixel.util.FlxSignal;
import funkin.data.Song;

// have you ever coded with your life on the line.

@:access(flixel.sound.FlxSound)
@:nullSafety(Off)
class SongAudio extends FlxBasic
{
	// sync tuning, all in ms except RESYNC_COOLDOWN which is in seconds btw
	// ms off before the clock just jumps to the audio
	static inline final SNAP_THRESHOLD:Float = 75;
	// ms the clock can run ahead while the audio position is stuck 
	static inline final MAX_EXTRAPOLATION:Float = 100;
	// how much of the error gets fixed per audio update 
	static inline final CLOCK_CORRECTION:Float = 0.1;
	// ms vocals can drift from master before getting reseeked 
	static inline final DRIFT_TOLERANCE:Float = 30;
	// seconds to wait after a resync before checking drift again 
	static inline final RESYNC_COOLDOWN:Float = 0.25;
	
	// instrumental, or the main track when trackSwap is on 
	public var inst(default, null):Null<FlxSoundEx> = null;
	// player vocals, or the combined voices file if the song doesn't split them 
	public var playerVocals(default, null):Null<FlxSoundEx> = null;
	// opponent vocals, or the miss track when trackSwap is on 
	public var opponentVocals(default, null):Null<FlxSoundEx> = null;
	
	// missing swaps from the main track to the miss track instead of muting vocals 
	public var trackSwap(default, null):Bool = false;
	// player and opponent vocals are separate tracks 
	public var splitVocals(default, null):Bool = false;
	// at least one vocal track is loaded, always false with trackSwap 
	public var hasVoices(default, null):Bool = false;
	
	// dispatched once the master track finishes 
	public final onComplete:FlxSignal = new FlxSignal();
	
	// true while the song is playing 
	public var playing(default, null):Bool = false;
	// true if paused with pause(), so resume() can pick back up 
	public var paused(default, null):Bool = false;
	
	// song position in ms, smoothed against the master track. setting it seeks every track 
	public var time(get, set):Float;
	// time extrapolated to right now, for reads in between syncs like input timing 
	public var liveTime(get, never):Float;
	// length of the master track in ms, 0 if nothing is loaded 
	public var length(get, never):Float;
	
	// playback rate for every track, locked to 1 without FLX_PITCH 
	public var pitch(default, set):Float = 1;
	// overall volume, multiplied into each track's own volume 
	public var volume(default, set):Float = 1;
	// volume of the inst track 
	public var instVolume(default, set):Float = 1;
	// volume of the player vocals 
	public var playerVolume(default, set):Float = 1;
	// volume of the opponent vocals, or the miss track with trackSwap 
	public var opponentVolume(default, set):Float = 1;
	// mutes player vocals while true, or swaps to the miss track with trackSwap 
	public var missed(default, set):Bool = false;
	
	final tracks:Array<FlxSoundEx> = [];
	
	// the track everything syncs to, inst if there is one, otherwise the first vocal track 
	var master:Null<FlxSoundEx> = null;
	// internal clock in ms, this is what time returns 
	var position:Float = 0;
	var lastStamp:Float = 0;
	// last master position seen, used to tell when the audio actually updated 
	var lastMasterTime:Float = -1;
	// drift checks are skipped until Timer.stamp() passes this 
	var nextResyncStamp:Float = 0;
	// set by the master's onComplete, handled on the next sync 
	var pendingComplete:Bool = false;
	// true if we paused because the window lost focus 
	var resumeOnFocus:Bool = false;
	
	// hooks into flixel's preUpdate and focus signals, so it doesn't need to be added to a state. call destroy() when done to unhook them 
	public function new()
	{
		super();
		visible = false;
		lastStamp = Timer.stamp();
		
		FlxG.signals.preUpdate.add(sync);
		FlxG.signals.focusLost.add(onFocusLost);
		FlxG.signals.focusGained.add(onFocusGained);
	}
	
	/**
	 * loads the inst and vocals for a song, unloading whatever was loaded before !
	 * @param song logs a warning and loads nothing if null
	 */
	public function load(song:Null<Song>):Void
	{
		unload();
		
		if (song == null)
		{
			Logger.log('Song provided was null. Cannot create tracks', WARN);
			return;
		}
		
		trackSwap = song.trackSwap ?? false;
		
		if (trackSwap)
		{
			inst = createTrack(Paths.trackSwap(song.song, 'main'));
			opponentVocals = createTrack(Paths.trackSwap(song.song, 'miss'));
		}
		else
		{
			inst = createTrack(Paths.inst(song.song));
			
			if (song.needsVoices)
			{
				playerVocals = createTrack(Paths.voices(song.song, 'player') ?? Paths.voices(song.song));
				opponentVocals = createTrack(Paths.voices(song.song, 'opp'));
			}
		}
		
		hasVoices = !trackSwap && (playerVocals != null || opponentVocals != null);
		splitVocals = playerVocals != null && opponentVocals != null;
		
		master = inst ?? playerVocals ?? opponentVocals;
		if (master != null) master.onComplete = onMasterComplete;
		
		applyVolumes();
		applyMissState();
	}
	
	// stops and destroys every track
	public function unload():Void
	{
		stop();
		
		for (track in tracks)
		{
			FlxG.sound.list.remove(track, true);
			track.destroy();
		}
		
		tracks.resize(0);
		inst = playerVocals = opponentVocals = master = null;
		trackSwap = splitVocals = hasVoices = false;
	}
	
	/**
	 * starts playback
	 * @param startTime ms to start from, if null it continues from the current time and does nothing if already playing
	 */
	public function play(?startTime:Float):Void
	{
		if (startTime != null) position = Math.max(0, startTime);
		else if (playing) return;
		
		playing = true;
		paused = false;
		pendingComplete = false;
		
		for (track in tracks)
			startTrack(track, position);
			
		resetClock();
	}
	
	// pauses every track, resume() picks back up from the same spot
	public function pause():Void
	{
		if (!playing) return;
		
		playing = false;
		paused = true;
		
		for (track in tracks)
			track.pause();
	}
	
	// resumes if paused, otherwise does nothing 
	public function resume():Void
	{
		if (paused) play();
	}
	
	// stops every track and resets time to 0
	public function stop():Void
	{
		playing = paused = pendingComplete = resumeOnFocus = false;
		position = 0;
		
		for (track in tracks)
			track.stop();
	}
	
	// snaps every track to the master right now instead of waiting for the drift check
	public function resync():Void
	{
		if (!playing || master == null || !master.playing) return;
		
		final masterTime = master._channel.position;
		
		for (track in tracks)
			if (track != master) alignTrack(track, masterTime);
		// i think
		nextResyncStamp = Timer.stamp() + RESYNC_COOLDOWN;
	}
	
	/**
	 * how far the most out of sync track is from the master
	 * @return drift in ms, 0 if not playing
	 */
	public function getDrift():Float
	{
		if (!playing || master == null || !master.playing) return 0;
		
		final masterTime = master._channel.position;
		var drift:Float = 0;
		
		for (track in tracks)
		{
			if (track == master || !track.playing) continue;
			drift = Math.max(drift, Math.abs(track._channel.position - masterTime));
		}
		
		return drift;
	}
	
	override function destroy():Void
	{
		FlxG.signals.preUpdate.remove(sync);
		FlxG.signals.focusLost.remove(onFocusLost);
		FlxG.signals.focusGained.remove(onFocusGained);
		
		unload();
		onComplete.destroy();
		
		super.destroy();
	}
	
	// runs every preUpdate, advances the clock and steers it toward the master's position
	function sync():Void
	{
		final now = Timer.stamp();
		final elapsedMs = (now - lastStamp) * 1000;
		lastStamp = now;
		
		if (pendingComplete)
		{
			complete();
			return;
		}
		
		if (!playing) return;
		
		final previous = position;
		position += elapsedMs * pitch;
		
		if (master == null) return;
		
		if (!master.playing)
		{
			position = Math.min(position, master.length);
			return;
		}
		
		final masterTime = master._channel.position;
		
		if (masterTime != lastMasterTime)
		{
			lastMasterTime = masterTime;
			
			final error = masterTime - position;
			
			if (Math.abs(error) > SNAP_THRESHOLD * Math.max(1, pitch)) position = masterTime;
			else position = Math.max(previous, position + error * CLOCK_CORRECTION);
		}
		else
		{
			position = Math.max(previous, Math.min(position, masterTime + MAX_EXTRAPOLATION * pitch));
		}
		
		if (now >= nextResyncStamp) correctDrift(masterTime, now);
	}
	
	// reseeks tracks that drifted past DRIFT_TOLERANCE and restarts ones that stopped early
	function correctDrift(masterTime:Float, now:Float):Void
	{
		final tolerance = DRIFT_TOLERANCE * Math.max(1, pitch);
		var corrected = false;
		
		for (track in tracks)
		{
			if (track == master || !track.exists || masterTime >= track.length - tolerance) continue;
			
			if (!track.playing || Math.abs(track._channel.position - masterTime) > tolerance)
			{
				alignTrack(track, masterTime);
				corrected = true;
			}
		}
		
		if (corrected) nextResyncStamp = now + RESYNC_COOLDOWN;
	}
	
	function onMasterComplete():Void
	{
		pendingComplete = true;
	}
	
	function complete():Void
	{
		pendingComplete = false;
		
		for (track in tracks)
			track.stop();
			
		playing = paused = false;
		position = length;
		
		onComplete.dispatch();
	}
	
	// resets timing state after play or a seek so the next sync starts clean
	function resetClock():Void
	{
		lastStamp = Timer.stamp();
		lastMasterTime = -1;
		nextResyncStamp = lastStamp + RESYNC_COOLDOWN;
	}
	
	function createTrack(sound:Null<Sound>):Null<FlxSoundEx>
	{
		if (sound == null) return null;
		
		final track = new FlxSoundEx();
		track.loadEmbedded(sound);
		#if FLX_PITCH
		track.pitch = pitch;
		#end
		
		FlxG.sound.list.add(track);
		tracks.push(track);
		
		return track;
	}
	
	function startTrack(track:FlxSoundEx, time:Float):Void
	{
		if (time < track.length) track.play(true, time);
		else track.stop();
	}
	
	// seeks a track to time, stops it if time is past its end, starts it if it wasn't playing
	function alignTrack(track:FlxSoundEx, time:Float):Void
	{
		if (time >= track.length) track.stop();
		else if (track.playing) track._channel.position = time;
		else track.play(true, time);
	}
	
	function applyVolumes():Void
	{
		setTrackVolume(inst, instVolume);
		setTrackVolume(playerVocals, playerVolume);
		setTrackVolume(opponentVocals, opponentVolume);
	}
	
	function applyMissState():Void
	{
		if (trackSwap)
		{
			setTrackMuted(inst, missed);
			setTrackMuted(opponentVocals, !missed);
		}
		else
		{
			setTrackMuted(playerVocals, missed);
		}
	}
	
	inline function setTrackVolume(track:Null<FlxSoundEx>, level:Float):Void
	{
		if (track != null && track.exists) track.volume = volume * level;
	}
	
	inline function setTrackMuted(track:Null<FlxSoundEx>, value:Bool):Void
	{
		if (track != null && track.exists && track.muted != value) track.muted = value;
	}
	
	function onFocusLost():Void
	{
		if (!FlxG.autoPause || !playing) return;
		
		pause();
		resumeOnFocus = true;
	}
	
	function onFocusGained():Void
	{
		if (!resumeOnFocus) return;
		
		resumeOnFocus = false;
		resume();
	}
	
	function get_time():Float return position;
	
	function set_time(value:Float):Float
	{
		position = Math.max(0, value);
		
		if (playing)
		{
			for (track in tracks)
				alignTrack(track, position);
				
			resetClock();
		}
		
		return position;
	}
	
	function get_liveTime():Float
	{
		return playing ? position + (Timer.stamp() - lastStamp) * 1000 * pitch : position;
	}
	
	function get_length():Float return master?.length ?? 0.0;
	
	function set_pitch(value:Float):Float
	{
		#if FLX_PITCH
		if (pitch == value) return value;
		
		pitch = value;
		
		for (track in tracks)
			track.pitch = value;
		#else
		pitch = 1;
		#end
		
		return pitch;
	}
	
	function set_volume(value:Float):Float
	{
		volume = value;
		applyVolumes();
		return value;
	}
	
	function set_instVolume(value:Float):Float
	{
		instVolume = value;
		applyVolumes();
		return value;
	}
	
	function set_playerVolume(value:Float):Float
	{
		playerVolume = value;
		applyVolumes();
		return value;
	}
	
	function set_opponentVolume(value:Float):Float
	{
		opponentVolume = value;
		applyVolumes();
		return value;
	}
	
	function set_missed(value:Bool):Bool
	{
		missed = value;
		applyMissState();
		return value;
	}
}
