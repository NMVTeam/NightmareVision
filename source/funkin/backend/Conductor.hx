package funkin.backend;

import funkin.data.Song;

typedef BPMChangeEvent =
{
	var stepTime:Int;
	var songTime:Float;
	var bpm:Float;
	@:optional var stepCrotchet:Float;
}

class Conductor
{
	public static var bpm(default, set):Float = 100;
	
	public static var visualPosition:Float = 0;
	public static var crotchet:Float = ((60 / bpm) * 1000); // beats in milliseconds
	public static var stepCrotchet:Float = crotchet / 4; // steps in milliseconds
	public static var songPosition:Float = 0;
	public static var offset:Float = 0;
	
	public static var ROWS_PER_BEAT = 48; // from Stepmania
	public static var BEATS_PER_MEASURE = 4; // TODO: time sigs
	public static var ROWS_PER_MEASURE = ROWS_PER_BEAT * BEATS_PER_MEASURE; // from Stepmania
	public static var MAX_NOTE_ROW = 1 << 30; // from Stepmania
	
	public inline static function beatToRow(beat:Float):Int return Math.round(beat * ROWS_PER_BEAT);
	
	public inline static function rowToBeat(row:Int):Float return row / ROWS_PER_BEAT;
	
	public inline static function secsToRow(sex:Float):Int return Math.round(getBeat(sex) * ROWS_PER_BEAT);
	
	// public static var safeFrames:Int = 10;
	public static var safeZoneOffset:Float = (ClientPrefs.safeFrames / 60) * 1000; // is calculated in create(), is safeFrames in milliseconds
	
	public static var bpmChangeMap:Array<BPMChangeEvent> = [];
	
	public function new() {}
	
	public inline static function beatToNoteRow(beat:Float):Int
	{
		return Math.round(beat * Conductor.ROWS_PER_BEAT);
	}
	
	public inline static function noteRowToBeat(row:Float):Float
	{
		return row / Conductor.ROWS_PER_BEAT;
	}
	
	public static function timeSinceLastBPMChange(time:Float):Float
	{
		var lastChange = getBPMFromSeconds(time);
		return time - lastChange.songTime;
	}
	
	public inline static function getBeatInMeasure(time:Float):Float
	{
		var lastBPMChange = getBPMFromSeconds(time);
		return (time - lastBPMChange.songTime) / (lastBPMChange.stepCrotchet * 4);
	}
	
	public inline static function getCrotchetAtTime(time:Float)
	{
		var lastChange = getBPMFromSeconds(time);
		return (lastChange.stepCrotchet * 4);
	}
	
	public inline static function getBPMFromSeconds(time:Float)
	{
		var lastChange:BPMChangeEvent = null;
		for (change in bpmChangeMap)
		{
			if (time >= change.songTime) lastChange = change;
		}
		
		return (lastChange ?? {stepTime: 0, songTime: 0, bpm: bpm, stepCrotchet: stepCrotchet});
	}
	
	public static function getBPMFromStep(step:Float)
	{
		var lastChange:BPMChangeEvent = null;
		for (change in bpmChangeMap)
		{
			if (change.stepTime <= step) lastChange = change;
		}
		
		return (lastChange ?? {stepTime: 0, songTime: 0, bpm: bpm, stepCrotchet: stepCrotchet});
	}
	
	public inline static function stepToSeconds(step:Float):Float
	{
		var lastChange = getBPMFromStep(step);
		return (lastChange.songTime + (step - lastChange.stepTime) * lastChange.stepCrotchet);
	}
	
	public inline static function beatToSeconds(beat:Float):Float
	{
		return stepToSeconds(beat * 4);
	}
	
	public inline static function getStep(time:Float)
	{
		var lastChange = getBPMFromSeconds(time);
		return (lastChange.stepTime + (time - lastChange.songTime) / lastChange.stepCrotchet);
	}
	
	public inline static function getStepRounded(time:Float)
	{
		return Math.floor(getStep(time));
	}
	
	public inline static function getBeat(time:Float)
	{
		return getStep(time) / 4;
	}
	
	public inline static function getBeatRounded(time:Float):Int
	{
		return Math.floor(getBeat(time));
	}
	
	public static function mapBPMChanges(song:Song)
	{
		bpmChangeMap.resize(0);
		bpmChangeMap.push({stepTime: 0, songTime: 0, bpm: song.bpm, stepCrotchet: calculateCrochet(song.bpm) / 4});
		
		var curBPM:Float = song.bpm;
		var totalSteps:Int = 0;
		var totalPos:Float = 0;
		for (i in 0...song.notes.length)
		{
			if (song.notes[i].changeBPM && song.notes[i].bpm != curBPM)
			{
				curBPM = song.notes[i].bpm;
				var event:BPMChangeEvent =
					{
						stepTime: totalSteps,
						songTime: totalPos,
						bpm: curBPM,
						stepCrotchet: calculateCrochet(curBPM) / 4
					};
				bpmChangeMap.push(event);
			}
			
			var deltaSteps:Int = Math.round(getSectionBeats(song, i) * 4);
			totalSteps += deltaSteps;
			totalPos += ((60 / curBPM) * 1000 / 4) * deltaSteps;
		}
	}
	
	inline static function getSectionBeats(song:Song, section:Int)
	{
		return (song.notes[section]?.sectionBeats ?? 4);
	}
	
	public inline static function calculateCrochet(bpm:Float)
	{
		return (60 / bpm) * 1000;
	}
	
	static function set_bpm(value:Float):Float
	{
		bpm = value;
		crotchet = calculateCrochet(bpm);
		stepCrotchet = (crotchet / 4);
		
		return bpm;
	}
}
