package funkin.audio;

// one vocal track loaded by SongAudio, made from a Voices-<name> file
@:allow(funkin.audio.SongAudio)
@:access(funkin.audio.SongAudio)
class SongTrack
{
	// the part after Voices- in the file name, empty for a plain Voices file
	public final name:String;
	// lane whose hits and misses mute this track, -1 if it isn't tied to one
	public final lane:Int;
	public final sound:FlxSoundEx;
	// this track's own volume, multiplied with its lane's volume and the overall volume
	public var volume(default, set):Float = 1;

	final audio:SongAudio;

	function new(audio:SongAudio, name:String, lane:Int, sound:FlxSoundEx)
	{
		this.audio = audio;
		this.name = name;
		this.lane = lane;
		this.sound = sound;
	}

	function set_volume(value:Float):Float
	{
		volume = value;
		audio.applyTrack(this);
		return value;
	}
}
