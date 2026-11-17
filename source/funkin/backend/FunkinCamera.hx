package funkin.backend;

import animate.internal.RenderTexture;

import flash.geom.ColorTransform;

import flixel.FlxCamera;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxShader;

import extensions.funkincrew.graphics.framebuffer.FixedBitmapData;
import extensions.funkincrew.graphics.shaders.RuntimeCustomBlendShader;

import openfl.display.OpenGLRenderer;
import openfl.Lib;
import openfl.display.BitmapData;
import openfl.display.BlendMode;

import flixel.graphics.tile.FlxDrawQuadsItem;
import flixel.graphics.tile.FlxDrawTrianglesItem;

using extensions.funkincrew.graphics.framebuffer.BitmapDataUtil;

/**
 * One queued `drawPixels` call waiting for a cross-camera shader blend.
 */
typedef DeferredBlend =
{
	var frame:Null<FlxFrame>;
	var pixels:Null<BitmapData>;
	var matrix:FlxMatrix;
	var transform:Null<ColorTransform>;
	var blend:Null<BlendMode>;
	var smoothing:Bool;
	var shader:Null<FlxShader>;
}

/**
 * A FlxCamera with additional powerful features:
 * - Added the ability to grab the camera screen as a `BitmapData` and use it as a texture.
 * - Added support for the following blend modes for a sprite through shaders:
 *   - DARKEN
 *   - HARDLIGHT
 *   - LIGHTEN
 *   - OVERLAY
 *   - DIFFERENCE
 *   - INVERT
 *   - COLORDODGE
 *   - COLORBURN
 *   - SOFTLIGHT
 *   - EXCLUSION
 *   - HUE
 *   - SATURATION
 *   - COLOR
 *   - LUMINOSITY
 */
@:nullSafety @:access(openfl.display.DisplayObject) @:access(openfl.display.BitmapData) @:access(openfl.display3D.Context3D) @:access(openfl.display3D.textures.TextureBase) @:access(flixel.graphics.FlxGraphic) @:access(flixel.graphics.frames.FlxFrame) @:access(openfl.display.OpenGLRenderer) @:access(openfl.geom.ColorTransform)
class FunkinCamera extends extensions.flixel.FlxCameraEx
{
	/**
	 * Whether or not the device supports the OpenGL extension `KHR_blend_equation_advanced`.
	 * If `false`, a shader implementation will be used to render certain blend modes.
	 */
	public static var hasKhronosExtension(get, never):Bool;
	
	static inline function get_hasKhronosExtension():Bool
	{
		#if FORCE_BLEND_SHADER
		return false;
		#else
		@:privateAccess
		return OpenGLRenderer.__complexBlendsSupported ?? false;
		#end
	}
	
	/**
	 * A list of blend modes that require the OpenGL extension `KHR_blend_equation_advanced`.
	 *
	 * NOTE:
	 *  - `LIGHTEN` is supported natively on desktop, but not other platforms.
	 *  - While `DARKEN` is supported natively on desktop, it causes issues with transparency.
	 */
	static final KHR_BLEND_MODES:Array<BlendMode> = [
		DARKEN,
		HARDLIGHT,
		#if !desktop LIGHTEN, #end
		OVERLAY,
		DIFFERENCE,
		COLORDODGE,
		COLORBURN,
		SOFTLIGHT,
		EXCLUSION,
		HUE,
		SATURATION,
		COLOR,
		LUMINOSITY
	];
	
	/**
	 * A list of blend modes that require the shader no matter what.
	 * This is due to these blend modes not being supported on any platform.
	 */
	static final SHADER_REQUIRED_BLEND_MODES:Array<BlendMode> = [INVERT];
	
	/**
	 * If `true` the blend shader will try to blend with the cameras underneath it.
	 * This is useful for, say, making a strumline note have a shader-only blend mode like `INVERT`.
	 *
	 * The blend is deferred until this camera renders.
	 * That way, it can see the full camera bitmap below it no matter what order the blend / sprites beneath were created. 
	 *
	 * Consecutive draws with the same blend mode and shader (like a sprite made of several tiles) are merged into a single blend pass.
	 * Useful for spritesheets with blends (i.e. Noise spritesheet with OVERLAY blend)
	 *
	 * Defaults to `false` since this can impact performance.
	 */
	public var crossCameraBlending:Bool;
	
	var _blendShader:RuntimeCustomBlendShader;
	var _backgroundFrame:FlxFrame;
	var _blendRenderTexture:RenderTexture;
	var _backgroundRenderTexture:RenderTexture;
	var _cameraTexture:FixedBitmapData;
	var _cameraMatrix:FlxMatrix;
	var _chainRenderTexture:RenderTexture;
	
	/**
	 * Cross-camera blends queued during the draw phase, drawn when this camera renders.
	 * 
	 * Done this way so ALL objects within a camera can have their blend mode applied, 
	 * instead of only objects drawn BEFORE the creation of the blend.
	 * (That is how funkin crew's implementation worked, at least when ported to this engine, which I find stupid)
	 */
	var _deferredBlends:Array<DeferredBlend> = [];
	
	@:nullSafety(Off)
	public function new(x:Int = 0, y:Int = 0, width:Int = 0, height:Int = 0, zoom:Float = 0)
	{
		super(x, y, width, height, zoom);
		
		_backgroundFrame = new FlxFrame(new FlxGraphic('', null));
		_backgroundFrame.frame = new FlxRect();
		
		_blendShader = new RuntimeCustomBlendShader();
		
		_backgroundRenderTexture = new RenderTexture(this.width, this.height);
		_blendRenderTexture = new RenderTexture(this.width, this.height);
		_chainRenderTexture = new RenderTexture(this.width, this.height);
		
		_cameraMatrix = new FlxMatrix();
		_cameraTexture = FixedBitmapData.create(this.width, this.height);
		
		crossCameraBlending = false;
	}
	
	override function drawPixels(?frame:FlxFrame, ?pixels:BitmapData, matrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode, ?smoothing:Bool = false, ?shader:FlxShader):Void
	{
		var shouldUseShader:Bool = (!hasKhronosExtension && KHR_BLEND_MODES.contains(blend)) || SHADER_REQUIRED_BLEND_MODES.contains(blend);
		
		// Fallback to the shader implementation if the device doesn't support `KHR_blend_equation_advanced`, or if
		// the specified blend mode requires the shader.
		if (shouldUseShader)
		{
			if (crossCameraBlending)
			{
				var matrixCopy:FlxMatrix = new FlxMatrix();
				matrixCopy.copyFrom(matrix);
				
				_deferredBlends.push(
					{
						frame: frame,
						pixels: pixels,
						matrix: matrixCopy,
						transform: copyColorTransform(transform),
						blend: blend,
						smoothing: smoothing ?? false,
						shader: shader
					});
					
				return;
			}
			
			_cameraTexture.drawCameraScreen(this);
			
			// clear this camera's graphics it'll get redrawn anyway
			this.clearDrawStack();
			this.canvas.graphics.clear();
			
			final entry = [
				{
					frame: frame,
					pixels: pixels,
					matrix: matrix,
					transform: transform,
					blend: blend,
					smoothing: smoothing ?? false,
					shader: shader
				}
			];
			blendPass(entry, _cameraTexture, _backgroundRenderTexture);
			queueResult(_backgroundRenderTexture, entry[0].smoothing);
		}
		else super.drawPixels(frame, pixels, matrix, transform, blend, smoothing, shader);
	}
	
	/**
	 * Passes the blend mode to blended objects via _blendShader
	 * Provided `entries` to allow multiple objects on a camera to have blends and all apply properly.
	 */
	function blendPass(entries:Array<DeferredBlend>, backdrop:BitmapData, target:RenderTexture):Void
	{
		_backgroundFrame.frame.set(0, 0, this.width, this.height);
		
		_blendRenderTexture.init(this.width, this.height);
		_blendRenderTexture.drawToCamera((camera, frameMatrix) -> {
			var pivotX:Float = width / 2;
			var pivotY:Float = height / 2;
			
			// this way it blends multiple objects instead of the first (or top) one
			for (entry in entries)
			{
				frameMatrix.copyFrom(entry.matrix);
				frameMatrix.translate(-pivotX, -pivotY);
				frameMatrix.scale(this.scaleX, this.scaleY);
				frameMatrix.translate(pivotX, pivotY);
				camera.drawPixels(entry.frame, entry.pixels, frameMatrix, entry.transform, null, entry.smoothing, entry.shader);
			}
		});
		_blendRenderTexture.render();
		
		_blendShader.sourceSwag = _blendRenderTexture.graphic.bitmap;
		_blendShader.backgroundSwag = backdrop;
		
		_blendShader.blendSwag = entries[0].blend;
		_blendShader.updateViewInfo(width, height, this);
		
		_backgroundFrame.parent.bitmap = _blendRenderTexture.graphic.bitmap;
		
		// On some displays, the DPI can be less than 1, which causes the blend shader to look bad
		// We just clamp the scale to 1 to avoid this!
		var clampedScale:Float = Math.max(1, Lib.current.stage.window.scale);
		
		target.init(Std.int(this.width * clampedScale), Std.int(this.height * clampedScale));
		target.drawToCamera((camera, matrix) -> {
			camera.zoom = this.zoom;
			matrix.scale(clampedScale, clampedScale);
			camera.drawPixels(_backgroundFrame, null, matrix, canvas.transform.colorTransform, null, false, _blendShader);
		});
		
		target.render();
	}
	
	/**
	 * Resizes the frame so it always fills the screen
	 */
	@:nullSafety(Off)
	function queueResult(result:RenderTexture, smoothing:Bool):Void
	{
		var clampedScale:Float = Math.max(1, Lib.current.stage.window.scale);
		
		_cameraMatrix.identity();
		_cameraMatrix.scale(1 / (this.scaleX * clampedScale), 1 / (this.scaleY * clampedScale));
		_cameraMatrix.translate(((width - width / this.scaleX) * 0.5), ((height - height / this.scaleY) * 0.5));
		
		super.drawPixels(result.graphic.imageFrame.frame, null, _cameraMatrix, null, null, smoothing, null);
	}
	
	/**
		* Flushes deferred cross-camera blends right before this camera draws its queue.
		* Cameras render in list order, so cameras underneath are already complete here.
		*
		* Blend groups are chained, meaning  the first one blends against the cameras underneath and each later one blends against the previous group's result. 
		*Only the final composite is queued, so blends stack instead of covering each other.
	 */
	override function render():Void
	{
		if (_deferredBlends.length > 0)
		{
			var pending = _deferredBlends;
			_deferredBlends = [];
			
			var thisIndex:Int = FlxG.cameras.list.indexOf(this);
			var camerasUnderneath = FlxG.cameras.list.slice(0, thisIndex);
			
			// fade and flash stopped appearing LOL
			// they still Dont sometimes but Shhh
			for (cam in camerasUnderneath)
				cam.drawFX();
				
			var captureList = camerasUnderneath.copy();
			captureList.push(this);
			_cameraTexture.drawCameraScreens(captureList);
			
			this.clearDrawStack();
			this.canvas.graphics.clear();
			
			var backdrop:BitmapData = _cameraTexture;
			var last:Null<RenderTexture> = null;
			
			var i:Int = 0;
			while (i < pending.length)
			{
				var group:Array<DeferredBlend> = [pending[i]];
				var j:Int = i + 1;
				
				while (j < pending.length && pending[j].blend == pending[i].blend && pending[j].shader == pending[i].shader)
				{
					group.push(pending[j]);
					j++;
				}
				
				var target:RenderTexture = (last == _backgroundRenderTexture) ? _chainRenderTexture : _backgroundRenderTexture;
				
				blendPass(group, backdrop, target);
				
				backdrop = target.graphic.bitmap;
				last = target;
				
				i = j;
			}
			
			if (last != null) queueResult(last, pending[0].smoothing);
		}
		
		super.render();
	}
	
	/**
		* Returns an exact copy of a provided `ColorTransform`
		* Honestly just code declutter
	**/
	static function copyColorTransform(source:Null<ColorTransform>):Null<ColorTransform>
	{
		if (source == null) return null;
		
		return new ColorTransform(source.redMultiplier, source.greenMultiplier, source.blueMultiplier, source.alphaMultiplier, source.redOffset, source.greenOffset, source.blueOffset,
			source.alphaOffset);
	}
	
	override function startQuadBatch(graphic:FlxGraphic, colored:Bool, hasColorOffsets:Bool = false, ?blend:BlendMode, smooth:Bool = false, ?shader:FlxShader):FlxDrawQuadsItem
	{
		// Can't batch complex non-coherent blends, so always force a new batch
		if (hasKhronosExtension && !(OpenGLRenderer.__coherentBlendsSupported ?? false) && KHR_BLEND_MODES.contains(blend))
		{
			var itemToReturn = null;
			
			if (FlxCamera._storageTilesHead != null)
			{
				itemToReturn = FlxCamera._storageTilesHead;
				var newHead = FlxCamera._storageTilesHead.nextTyped;
				itemToReturn.reset();
				FlxCamera._storageTilesHead = newHead;
			}
			else
			{
				itemToReturn = new FlxDrawQuadsItem();
			}
			
			// TODO: catch this error when the dev actually messes up, not in the draw phase
			if (graphic.isDestroyed) throw 'Cannot queue ${graphic.key}. This sprite was destroyed.';
			
			itemToReturn.graphics = graphic;
			itemToReturn.antialiasing = smooth;
			itemToReturn.colored = colored;
			itemToReturn.hasColorOffsets = hasColorOffsets;
			itemToReturn.blend = blend;
			@:nullSafety(Off)
			itemToReturn.shader = shader;
			
			itemToReturn.nextTyped = _headTiles;
			_headTiles = itemToReturn;
			
			if (_headOfDrawStack == null)
			{
				_headOfDrawStack = itemToReturn;
			}
			
			if (_currentDrawItem != null)
			{
				_currentDrawItem.next = itemToReturn;
			}
			
			_currentDrawItem = itemToReturn;
			
			return itemToReturn;
		}
		
		return super.startQuadBatch(graphic, colored, hasColorOffsets, blend, smooth, shader);
	}
	
	override function startTrianglesBatch(graphic:FlxGraphic, smoothing:Bool = false, isColored:Bool = false, ?blend:BlendMode, ?hasColorOffsets:Bool, ?shader:FlxShader):FlxDrawTrianglesItem
	{
		// Can't batch complex non-coherent blends, so always force a new batch
		if (hasKhronosExtension
			&& !(OpenGLRenderer.__coherentBlendsSupported ?? false)
			&& KHR_BLEND_MODES.contains(blend)) return getNewDrawTrianglesItem(graphic, smoothing, isColored, blend, hasColorOffsets, shader);
			
		return super.startTrianglesBatch(graphic, smoothing, isColored, blend, hasColorOffsets, shader);
	}
	
	/**
	 * Drops deferred blends juuust in case
	 */
	override function clearDrawStack():Void
	{
		_deferredBlends = [];
		super.clearDrawStack();
	}
	
	@:nullSafety(Off)
	override function destroy():Void
	{
		super.destroy();
		
		_deferredBlends = [];
		
		// sigh just in case
		if (_blendShader != null)
		{
			_blendShader.sourceSwag = null;
			_blendShader.backgroundSwag = null;
			_blendShader = null;
		}
		
		if (_blendRenderTexture != null)
		{
			_blendRenderTexture.destroy();
			_blendRenderTexture = null;
		}
		
		if (_backgroundRenderTexture != null)
		{
			_backgroundRenderTexture.destroy();
			_backgroundRenderTexture = null;
		}
		
		if (_chainRenderTexture != null)
		{
			_chainRenderTexture.destroy();
			_chainRenderTexture = null;
		}
		
		if (_cameraTexture != null)
		{
			_cameraTexture.dispose();
			_cameraTexture = null;
		}
		
		_backgroundFrame = null;
		_cameraMatrix = null;
	}
}
