#if macro
  import haxe.macro.Expr;
  using tink.MacroApi;
#end

class Should {
  macro static public function notCompile(e:Expr, reason:Expr) {
    var test = 
      switch reason.expr {
        case EConst(CRegexp(s, f)):
          var regex = new EReg(s, f);
          function (msg:String) {
            if (!regex.match(msg))
              reason.reject('Compilation did fail, but expected pattern is not met by "$msg"');
          } 
        default:
          reason.reject('should be a regex literal');
      }

    switch e.typeof() {
      case Success(_): e.reject('Expression compiled, even though it should not');
      case Failure(e): test(e.message);
    }
    return macro assertTrue(true);
  }
}