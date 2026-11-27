package funkin.audio;

import flixel.util.FlxSignal;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.sound.FlxSound;

import funkin.data.Song;

/**
 * Container of FlxSounds with some functions to make multiple tracks act as one
 */
@:nullSafety(Strict)
class SyncedFlxSoundGroup extends FlxTypedGroup<FlxSound>
{
	// // make this work later lol
	// public var onFinish:FlxSignal;
	
	/**
	 * Set volume to a value between 0 and 1 to change how this sound is.
	 */
	public var volume(get, set):Float;
	
	/**
	 * Set pitch, which also alters the playback speed. Default is 1.
	 */
	public var pitch(get, set):Float;
	
	/**
	 * The position in runtime of the music playback in milliseconds.
	 * If set while paused, changes only come into effect after a `resume()` call.
	 */
	public var time(get, set):Float;
	
	/**
	 * Whether or not the sound is currently playing.
	 */
	public var playing(get, never):Bool;
	
	public var songLength(get, never):Float;
	
	@:inheritDoc(flixel.sound.FlxSound.resume)
	public function resume() forEachAlive(snd -> snd.resume());
	
	@:inheritDoc(flixel.sound.FlxSound.pause)
	public function pause() forEachAlive(snd -> snd.pause());
	
	@:inheritDoc(flixel.sound.FlxSound.play)
	public function play(forceRestart:Bool = false, startTime:Float = 0.0, ?endTime:Null<Float>) forEachAlive(snd -> snd.play(forceRestart, startTime, endTime));
	
	@:inheritDoc(flixel.sound.FlxSound.stop)
	public function stop() forEachAlive(snd -> snd.stop());
	
	public function new()
	{
		super();
	}
	
	/**
	 * Adds a new FlxSound instance to the group 
	 * @param sound The FlxSound instance
	 * @return FlxSound
	 */
	override function add(sound:FlxSound):FlxSound
	{
		var snd = super.add(sound);
		if (snd == null) return snd;
		
		// copy the group settings
		snd.time = time;
		snd.pitch = pitch;
		snd.volume = volume;
		if (snd != getFirstAlive()) snd.endTime = snd.length;
		
		FlxG.sound.list.add(snd);
		
		return snd;
	}
	
	/**
	 * Culls through the group to find the largest delta
	 * @param baseTime The reference to compare delta towards. Defaults to the groups first instance's time
	 */
	public function getDesyncDifference(?baseTime:Float):Float
	{
		final time = baseTime ?? getFirstAlive()?.time ?? 0.0;
		
		var highestDiff:Float = 0;
		forEachAlive(snd -> {
			if (time > snd.length) return;
			
			final delta = Math.abs(snd.time - time);
			if (delta > highestDiff) highestDiff = delta; // get the highest difference
		});
		
		return highestDiff;
	}
	
	/**
	 * Resyncs all group members to a given time. 
	 * @param baseTime The reference to compare difference to. Defaults to the groups first instance's time
	 */
	public function resync(?baseTime:Float)
	{
		final time = baseTime ?? getFirstAlive()?.time ?? 0.0;
		
		forEachAlive(snd -> {
			if (time > snd.length) return;
			
			snd.pause();
			snd.time = time;
			snd.play(false, time);
		});
	}
	
	@:inheritDoc
	override function destroy()
	{
		stop();
		super.destroy();
	}
	
	@:inheritDoc
	override function clear()
	{
		stop();
		super.clear();
	}
	
	function set_volume(value:Float):Float
	{
		forEachAlive(snd -> snd.volume = value);
		return value;
	}
	
	function get_volume():Float return getFirstAlive()?.volume ?? 1.0;
	
	function set_pitch(value:Float):Float
	{
		#if FLX_PITCH
		forEachAlive(snd -> snd.pitch = value);
		#else
		return 1.0;
		#end
		
		return value;
	}
	
	function get_pitch():Float return #if FLX_PITCH getFirstAlive()?.pitch ?? 1.0 #else 1.0 #end;
	
	function set_time(value:Float):Float
	{
		forEachAlive(snd -> snd.time = value);
		return value;
	}
	
	function get_time():Float return getFirstAlive()?.time ?? 0.0;
	
	function get_playing():Bool return getFirstAlive()?.playing ?? false;
	
	function get_songLength():Float return getFirstAlive()?.length ?? 0.0;
}

// specialized ver
class VocalGroup extends SyncedFlxSoundGroup
{
	public var playerVocals:SyncedFlxSoundGroup; // sound groups inside sound groups hype
	public var opponentVocals:SyncedFlxSoundGroup;
	
	public var playerVolume(get, set):Float;
	
	public var opponentVolume(get, set):Float;
	
	public function new()
	{
		super();
		playerVocals = new SyncedFlxSoundGroup();
		opponentVocals = new SyncedFlxSoundGroup();
	}
	
	public function addOpponentVocals(?sound:flixel.sound.FlxSound)
	{
		if (sound == null) return null;
		opponentVocals.add(sound);
		return add(sound);
	}
	
	public function addPlayerVocals(?sound:flixel.sound.FlxSound)
	{
		if (sound == null) return null;
		playerVocals.add(sound);
		return add(sound);
	}
	
	function set_playerVolume(value:Float):Float
	{
		if (playerVocals != null) playerVocals.volume = value;
		return value;
	}
	
	function get_playerVolume():Float return playerVocals?.volume ?? 1.0;
	
	function set_opponentVolume(value:Float):Float
	{
		if (opponentVocals != null) opponentVocals.volume = value;
		return value;
	}
	
	function get_opponentVolume():Float return opponentVocals?.volume ?? 1.0;
	
	override function clear()
	{
		opponentVocals.clear();
		playerVocals.clear();
		super.clear();
	}
	
	override function destroy()
	{
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
		playerVocals = FlxDestroyUtil.destroy(playerVocals);
		
		super.destroy();
	}
}

@:nullSafety(Strict)
class PlayableSong extends VocalGroup
{
	/**
	 * The instrumental of the song.
	 */
	public var inst:Null<FlxSound> = null;
	
	public final onComplete:FlxSignal = new FlxSignal();
	
	/**
	 * If true, the Inst is considered
	 */
	public var trackSwap:Bool = false;
	
	public var localTime:Float = 0;
	public var maxDesyncDelta:Float = 35.0;
	
	public var splitVocals:Bool = false;
	public var hasVoices:Bool = false;
	public var isPlaying:Bool = false;
	
	/**
	 * Loads an Inst, Vocals, Enemy track from a `Song` data
	 */
	public function loadSong(?data:Song):Void
	{
		volume = 1;
		
		if (data == null)
		{
			Logger.log('Song provided was null. Cannot create tracks', WARN);
			
			return;
		}
		
		volume = 1;
		
		splitVocals = false;
		trackSwap = data.trackSwap ?? false;
		
		if (trackSwap)
		{
			final instSnd = Paths.trackSwap(data.song, 'main');
			if (instSnd != null)
			{
				inst = add(new FlxSoundEx().loadEmbedded(instSnd));
			}
			
			final missTrack = Paths.trackSwap(data.song, 'miss');
			if (missTrack != null) addOpponentVocals(new FlxSoundEx().loadEmbedded(missTrack));
			
			opponentVolume = 0;
			return;
		}
		
		inst = add(new FlxSoundEx().loadEmbedded(Paths.inst(data.song)));
		
		if (!data.needsVoices)
		{
			return;
		}
		
		final playerSound = Paths.voices(data.song, 'player') ?? Paths.voices(data.song);
		
		if (playerSound != null)
		{
			addPlayerVocals(new FlxSoundEx().loadEmbedded(playerSound));
		}
		
		final opponentSound = Paths.voices(data.song, 'opp');
		
		if (opponentSound != null)
		{
			addOpponentVocals(new FlxSoundEx().loadEmbedded(opponentSound));
		}
		
		hasVoices = true;
		splitVocals = playerVocals.length != 0 && opponentVocals.length != 0;
	}
	
	override public function play(forceRestart:Bool = false, startTime:Float = 0.0, ?endTime:Null<Float>)
	{
		if (trackSwap && inst != null) inst.volume = 0;
		if (endTime == null || endTime == 0) endTime = songLength; // ?
		
		isPlaying = true;
		localTime = this.time;
		super.play(forceRestart, startTime, endTime);
	}
	
	override public function stop()
	{
		isPlaying = false;
		super.stop();
	}
	
	/**
	 * Updates track volume to mute the `Opponent` track when the user misses.
	 */
	public function miss()
	{
		setTrackVolumeState(true);
	}
	
	/**
	 * Updates track volume to unmute the `Player` track when the user hits a note.
	 */
	public function hit()
	{
		setTrackVolumeState(false);
	}
	
	/**
	 * Updates the tracks volume based on if the player has missed or not
	 * @param hasMissed 
	 */
	public function setTrackVolumeState(hasMissed:Bool = false):Void // TODO: good docs
	{
		if (trackSwap)
		{
			if (inst != null) inst.volume = hasMissed ? 0 : 1;
			opponentVolume = hasMissed ? 1 : 0;
		}
		else playerVolume = hasMissed ? 0 : 1;
	}
	
	inline function isSoundPlaying(snd:FlxSound):Bool
	{
		if (snd == null) return false;
		
		return isPlaying && snd.playing && snd.length > localTime;
	}
	
	public function getLongestLength():Float
	{
		var length:Float = 0.0;
		for (snd in members)
			length = Math.max(length, snd.length);
			
		return length;
	}
	
	override public function resync(?baseTime:Float)
	{
		super.resync(baseTime);
		localTime = this.time;
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		if (isPlaying)
		{
			localTime += elapsed * 1000 * pitch;
			
			if (localTime > inst?.length ?? 0)
			{
				stop();
				onComplete.dispatch();
				isPlaying = false;
			}
		}
	}
	
	override function destroy()
	{
		onComplete.removeAll();
		super.destroy();
	}
}
