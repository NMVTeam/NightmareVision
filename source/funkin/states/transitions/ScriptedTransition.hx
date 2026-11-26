package funkin.states.transitions;

import funkin.backend.BaseTransitionState;
import funkin.backend.MusicBeatState;

class ScriptedTransition extends BaseTransitionState
{
	public static var scriptKey:String = '';
	
	override function create()
	{
		scriptPrefix = 'transitions';
		initStateScript(scriptKey, false);
		
		// just in case cuz for some reason its diddy
		scriptGroup.set('dispatchFinish', dispatchFinish);
		super.create();
		
		scriptGroup.call('onLoad', []);
	}
}
