@import Cocoa ;
@import LuaSkin ;

// NOTE: This is from MJConsoleWindowController

#define MJColorForStdout [NSColor colorWithCalibratedHue:0.88 saturation:1.0 brightness:0.6 alpha:1.0]

@interface MJConsoleWindowController : NSWindowController

+ (instancetype)singleton;
- (void)setup;

@end

@interface MJConsoleWindowController ()

@property NSMutableArray *history;
@property NSInteger historyIndex;
@property IBOutlet NSTextView *outputView;
@property (weak) IBOutlet NSTextField *inputField;
@property NSMutableArray *preshownStdouts;

@end

static int refTable = LUA_NOREF;

/// hs.console.hswindow() -> hs.window object
/// Function
/// Get an hs.window object which represents the Hammerspoon console window
///
/// Parameters:
///  * None
///
/// Returns:
///  * an hs.window object
static int console_asWindow(lua_State *L) {
    LuaSkin *skin     = [LuaSkin shared];
    NSWindow *console = [[MJConsoleWindowController singleton] window];

    CGWindowID windowID = (CGWindowID)[console windowNumber];
    [skin requireModule:"hs.window"];
    lua_getfield(L, -1, "windowForID");
    lua_pushinteger(L, windowID);
    lua_call(L, 1, 1);
    return 1;
}

/// hs.console.windowBackgroundColor([color]) -> color
/// Function
/// Get or set the color for the background of the Hammerspoon Console's window.
///
/// Parameters:
/// * color - an optional table containing color keys as described in `hs.drawing.color`
///
/// Returns:
/// * the current color setting as a table
///
/// Notes:
///  * See the `hs.drawing.color` entry in the Dash documentation, or type `help.hs.drawing.color` in the Hammerspoon console to get more information on how to specify a color.
static int console_backgroundColor(lua_State *L) {
    LuaSkin *skin     = [LuaSkin shared];
    NSWindow *console = [[MJConsoleWindowController singleton] window];

    if (lua_type(L, 1) != LUA_TNONE) {
        luaL_checktype(L, 1, LUA_TTABLE);
        [console setBackgroundColor:[skin luaObjectAtIndex:1 toClass:"NSColor"]];
    }

    [skin pushNSObject:[console backgroundColor]];
    return 1;
}

/// hs.console.outputBackgroundColor([color]) -> color
/// Function
/// Get or set the color for the background of the Hammerspoon Console's output view.
///
/// Parameters:
/// * color - an optional table containing color keys as described in `hs.drawing.color`
///
/// Returns:
/// * the current color setting as a table
///
/// Notes:
///  * See the `hs.drawing.color` entry in the Dash documentation, or type `help.hs.drawing.color` in the Hammerspoon console to get more information on how to specify a color.
static int console_outputBackgroundColor(lua_State *L) {
    LuaSkin *skin      = [LuaSkin shared];
    NSTextView *output = [MJConsoleWindowController singleton].outputView;

    if (lua_type(L, 1) != LUA_TNONE) {
        luaL_checktype(L, 1, LUA_TTABLE);
        [output setBackgroundColor:[skin luaObjectAtIndex:1 toClass:"NSColor"]];
    }

    [skin pushNSObject:[output backgroundColor]];
    return 1;
}

/// hs.console.inputBackgroundColor([color]) -> color
/// Function
/// Get or set the color for the background of the Hammerspoon Console's input field.
///
/// Parameters:
/// * color - an optional table containing color keys as described in `hs.drawing.color`
///
/// Returns:
/// * the current color setting as a table
///
/// Notes:
///  * See the `hs.drawing.color` entry in the Dash documentation, or type `help.hs.drawing.color` in the Hammerspoon console to get more information on how to specify a color.
static int console_inputBackgroundColor(lua_State *L) {
    LuaSkin *skin      = [LuaSkin shared];
    NSTextField *input = [MJConsoleWindowController singleton].inputField;

    if (lua_type(L, 1) != LUA_TNONE) {
        luaL_checktype(L, 1, LUA_TTABLE);
        [input setBackgroundColor:[skin luaObjectAtIndex:1 toClass:"NSColor"]];
    }

    [skin pushNSObject:[input backgroundColor]];
    return 1;
}

/// hs.console.smartInsertDeleteEnabled([flag]) -> bool
/// Function
/// Determine whether or not objects copied from the console window insert or delete space around selected words to preserve proper spacing and punctuation.
///
/// Parameters:
///  * flag - an optional boolean value indicating whether or not "smart" space behavior is enabled when copying from the Hammerspoon console.
///
/// Returns:
///  * the current value
///
/// Notes:
///  * this only applies to future copy operations from the Hammerspoon console -- anything already in the clipboard is not affected.
static int console_smartInsertDeleteEnabled(lua_State *L) {
    NSTextView *output = [MJConsoleWindowController singleton].outputView;

    if (lua_type(L, 1) != LUA_TNONE) {
        [output setSmartInsertDeleteEnabled:(BOOL)lua_toboolean(L, 1)];
    }

    lua_pushboolean(L, [output smartInsertDeleteEnabled]);
    return 1;
}

/// hs.console.getHistory() -> array
/// Function
/// Get the Hammerspoon console history as an array.
///
/// Parameters:
///  * None
///
/// Returns:
///  * an array containing the history of commands entered into the Hammerspoon console.
static int console_getHistory(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TBREAK];
    MJConsoleWindowController *console = [MJConsoleWindowController singleton];

    [skin pushNSObject:[console history]];
    return 1;
}

/// hs.console.setConsole([styledText]) -> none
/// Function
/// Clear the Hammerspoon console output window.
///
/// Parameters:
///  * styledText - an optional `hs.styledtext` object containing the text you wish to replace the Hammerspoon console output with.  If you do not provide an argument, the console is cleared of all content.
///
/// Returns:
///  * None
///
/// Notes:
///  * You can specify the console content as a string or as an `hs.styledtext` object in either userdata or table format.
static int console_setConsole(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TANY | LS_TOPTIONAL, LS_TBREAK];
    MJConsoleWindowController *console = [MJConsoleWindowController singleton];

    if (lua_gettop(L) == 0) {
        [[console.outputView textStorage] performSelectorOnMainThread:@selector(setAttributedString:)
                                                           withObject:[[NSMutableAttributedString alloc] init]
                                                        waitUntilDone:YES];
    } else {
        NSAttributedString *theStr;
        if (lua_type(L, 1) == LUA_TUSERDATA && luaL_testudata(L, 1, "hs.styledtext")) {
            theStr = [skin luaObjectAtIndex:1 toClass:"NSAttributedString"];
        } else {
            NSDictionary *consoleAttrs = @{ NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12.0],
                                            NSForegroundColorAttributeName: MJColorForStdout };
            luaL_tolstring(L, 1, NULL);
            theStr = [[NSAttributedString alloc] initWithString:[skin toNSObjectAtIndex:-1]
                                                     attributes:consoleAttrs];
            lua_pop(L, 1);
        }
        [[console.outputView textStorage] performSelectorOnMainThread:@selector(setAttributedString:)
                                                           withObject:theStr
                                                        waitUntilDone:YES];
    }
    [console.outputView scrollToEndOfDocument:console];
    return 0;
}

/// hs.console.getConsole([styled]) -> text | styledText
/// Function
/// Get the text of the Hammerspoon console output window.
///
/// Parameters:
///  * styled - an optional boolean indicating whether the console text is returned as a string or a styledText object.  Defaults to false.
///
/// Returns:
///  * The text currently in the Hammerspoon console output window as either a string or an `hs.styledtext` object.
///
/// Notes:
///  * If the text of the console is retrieved as a string, no color or style information in the console output is retrieved - only the raw text.
static int console_getConsole(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TBOOLEAN | LS_TOPTIONAL, LS_TBREAK];
    MJConsoleWindowController *console = [MJConsoleWindowController singleton];
    BOOL styled                        = lua_isboolean(L, 1) ? (BOOL)lua_toboolean(L, 1) : NO;

    if (styled) {
        [skin pushNSObject:[[console.outputView textStorage] copy]];
    } else {
        [skin pushNSObject:[[console.outputView textStorage] string]];
    }

    return 1;
}

/// hs.console.setHistory(array) -> nil
/// Function
/// Set the Hammerspoon console history to the items specified in the given array.
///
/// Parameters:
///  * array - the list of commands to set the Hammerspoon console history to.
///
/// Returns:
///  * None
///
/// Notes:
///  * You can clear the console history by using an empty array (e.g. `hs.console.setHistory({})`
static int console_setHistory(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TTABLE, LS_TBREAK];
    MJConsoleWindowController *console = [MJConsoleWindowController singleton];

    console.history      = [skin toNSObjectAtIndex:1];
    console.historyIndex = (NSInteger)[console.history count];
    lua_pushnil(L);
    return 1;
}

/// hs.console.printStyledtext(...) -> none
/// Function
/// A print function which recognizes `hs.styledtext` objects and renders them as such in the Hammerspoon console.
///
/// Parameters:
///  * Any number of arguments can be specified, just like the builtin Lua `print` command.  If an argument matches the userdata type of `hs.styledtext`, the text is rendered as defined by its style attributes in the Hammerspoon console; otherwise it is rendered as it would be via the traditional `print` command within Hammerspoon.
///
/// Returns:
///  * None
///
/// Notes:
///  * This has been made as close to the Lua `print` command as possible.  You can replace the existing print command with this by adding the following to your `init.lua` file:
///
/// ~~~
///    print = function(...)
///        hs.rawprint(...)
///        hs.console.printStyledtext(...)
///    end
/// ~~~
static int console_printStyledText(lua_State *L) {
    LuaSkin *skin                      = [LuaSkin shared];
    MJConsoleWindowController *console = [MJConsoleWindowController singleton];
    NSDictionary *consoleAttrs         = @{ NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12.0],
                                    NSForegroundColorAttributeName: MJColorForStdout };

    NSMutableAttributedString *theStr = [[NSMutableAttributedString alloc] init];
    for (int i = 1; i <= lua_gettop(L); i++) {
        if (i > 1) {
            [theStr appendAttributedString:[[NSAttributedString alloc] initWithString:@"\t"
                                                                           attributes:consoleAttrs]];
        }
        if (lua_type(L, i) == LUA_TUSERDATA && luaL_testudata(L, i, "hs.styledtext")) {
            [theStr appendAttributedString:[skin luaObjectAtIndex:i toClass:"NSAttributedString"]];
        } else {
            luaL_tolstring(L, i, NULL);
            [theStr appendAttributedString:[[NSAttributedString alloc]
                                               initWithString:[skin toNSObjectAtIndex:-1]
                                                   attributes:consoleAttrs]];
            lua_pop(L, 1);
        }
    }
    [theStr appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                                                                   attributes:consoleAttrs]];

    [[console.outputView textStorage] performSelectorOnMainThread:@selector(appendAttributedString:)
                                                       withObject:theStr
                                                    waitUntilDone:YES];
    [console.outputView scrollToEndOfDocument:console];
    return 0;
}

/// hs.console.level([theLevel]) -> currentValue
/// Function
/// Get or set the console window level
///
/// Parameters:
///  * `theLevel` - an optional parameter specifying the desired level as an integer, which can be obtained from `hs.drawing.windowLevels`.
///
/// Returns:
///  * the current, possibly new, value
///
/// Notes:
///  * see the notes for `hs.drawing.windowLevels`
static int console_level(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER | LS_TINTEGER | LS_TOPTIONAL, LS_TBREAK] ;
    NSWindow *console = [[MJConsoleWindowController singleton] window];

    if (lua_gettop(L) == 1) {
        lua_Integer targetLevel = lua_tointeger(L, 1) ;

        if (targetLevel >= CGWindowLevelForKey(kCGMinimumWindowLevelKey) && targetLevel <= CGWindowLevelForKey(kCGMaximumWindowLevelKey)) {
            [console setLevel:targetLevel] ;
        } else {
            return luaL_error(L, [[NSString stringWithFormat:@"window level must be between %d and %d inclusive",
                                   CGWindowLevelForKey(kCGMinimumWindowLevelKey),
                                   CGWindowLevelForKey(kCGMaximumWindowLevelKey)] UTF8String]) ;
        }
    }
    lua_pushinteger(L, console.level) ;
    return 1 ;
}

/// hs.console.alpha([alpha]) -> currentValue
/// Function
/// Get or set the alpha level of the console window.
///
/// Parameters:
///  * `alpha` - an optional number between 0.0 and 1.0 specifying the new alpha level for the Hammerspoon console.
///
/// Returns:
///  * the current, possibly new, value.
static int console_alpha(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER | LS_TOPTIONAL, LS_TBREAK] ;
    NSWindow *console = [[MJConsoleWindowController singleton] window];

    if (lua_gettop(L) == 1) {
        CGFloat newLevel = luaL_checknumber(L, 1);
        console.alphaValue = ((newLevel < 0.0) ? 0.0 : ((newLevel > 1.0) ? 1.0 : newLevel)) ;
    }
    lua_pushnumber(L, console.alphaValue) ;
    return 1 ;
}

/// hs.console.behavior([behavior]) -> currentValue
/// Method
/// Get or set the window behavior settings for the console.
///
/// Parameters:
///  * `behavior` - an optional number representing the desired window behaviors for the Hammerspoon console.
///
/// Returns:
///  * the current, possibly new, value.
///
/// Notes:
///  * Window behaviors determine how the webview object is handled by Spaces and Exposé. See `hs.drawing.windowBehaviors` for more information.
static int console_behavior(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER | LS_TOPTIONAL,
                    LS_TBREAK] ;

    NSWindow *console = [[MJConsoleWindowController singleton] window];

    if (lua_gettop(L) == 1) {
        [skin checkArgs:LS_TNUMBER | LS_TINTEGER,
                        LS_TBREAK] ;

        NSInteger newLevel = lua_tointeger(L, 1);
        @try {
            [console setCollectionBehavior:(NSWindowCollectionBehavior)newLevel] ;
        }
        @catch ( NSException *theException ) {
            return luaL_error(L, "%s: %s", [[theException name] UTF8String], [[theException reason] UTF8String]) ;
        }
    }
    lua_pushinteger(L, [console collectionBehavior]) ;
    return 1 ;
}

// static int meta_gc(__unused lua_State *L) {
//     return 0;
// }

static const luaL_Reg extrasLib[] = {
//     {"asHSDrawing", console_asDrawing},
    {"hswindow", console_asWindow},

    {"windowBackgroundColor", console_backgroundColor},
    {"inputBackgroundColor", console_inputBackgroundColor},
    {"outputBackgroundColor", console_outputBackgroundColor},

    {"smartInsertDeleteEnabled", console_smartInsertDeleteEnabled},
    {"getHistory", console_getHistory},
    {"setHistory", console_setHistory},

    {"getConsole", console_getConsole},
    {"setConsole", console_setConsole},

    {"level", console_level},
    {"alpha", console_alpha},
    {"behavior", console_behavior},

    {"printStyledtext", console_printStyledText},
    {NULL, NULL}};

// static const luaL_Reg metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

int luaopen_hs_console_internal(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared];
    refTable      = [skin registerLibrary:extrasLib metaFunctions:nil];

    return 1;
}
