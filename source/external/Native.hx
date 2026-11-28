package external;

// dumping this here is a bit gross but for now ill leave it as so
#if (windows && cpp)
@:buildXml('
<target id="haxe">
	<lib name="wininet.lib" if="windows" />
	<lib name="dwmapi.lib" if="windows" />
</target>
')
@:cppFileCode('
#define WIN32_LEAN_AND_MEAN

#include <dwmapi.h>
#include <windows.h>
#include <winuser.h>

#include <psapi.h>

#pragma comment(lib, "Shell32.lib")
extern "C" HRESULT WINAPI SetCurrentProcessExplicitAppUserModelID(PCWSTR AppID);
')
#end
class Native
{
	/**
	 * Attempts to retrieve the actual task memory used by the application
	 * 
	 * Will fallback on `0.0` if it is not supported.
	 */
	public static function getTaskMemory():external.memory.Memory.MemoryT
	{
		#if cpp
		return external.memory.Memory.getCurrentUsage();
		#else
		return 0;
		#end
	}
	
	/**
	 * Sets the window to either `Dark` or `Light` mode
	 * 
	 * only supported on windows
	 * @param isDark 
	 */
	public static function setDarkMode(value:Bool)
	{
		#if (windows && cpp)
		final dark:Int = value ? 1 : 0;
		untyped __cpp__("
                int darkMode = dark;
                HWND window = GetActiveWindow();
                if (S_OK != DwmSetWindowAttribute(window, 19, &darkMode, sizeof(darkMode))) {
                    DwmSetWindowAttribute(window, 20, &darkMode, sizeof(darkMode));
                }
                UpdateWindow(window);
            ");
		#end
	}
}
