package tink.anon;

#if macro
import haxe.macro.Type;
import haxe.macro.Expr;

using StringTools;
using tink.MacroApi;
using tink.CoreApi;
#end

class Macro {
  static public function mergeExpressions(exprs:Array<Expr>, ?requiredType, ?pos, ?as) {
    var complex = [],
        individual = [];

    function add(name, expr, pos)
      individual.push({ name: name, getValue: function (_) return expr, pos: pos });

    for (e in exprs) 
      switch e {
        case macro $name = $v:
          add(name.getIdent().sure(), v, name.pos);

        case { expr: EObjectDecl(fields) }:

          for (f in fields)
            add(f.field, f.expr, f.expr.pos);

        default: 
          complex.push(e);
      }
    
    return mergeParts(individual, complex, requiredType, pos, as);
  }

  static public function mergeParts(
    individual:Array<{ name:String, pos:Position, getValue:Option<Type>->Expr }>, 
    complex:Array<Expr>,
    ?requiredType:String->Outcome<Option<Type>, Error>, 
    ?pos:Position, 
    ?as:ComplexType
  ) {
    var fields = [],
        args = [],
        callArgs = [],
        exists = new Map();

    if (requiredType == null)
      requiredType = function (_) return Success(None);

    var ret = EObjectDecl(fields).at(pos).func(args, as).asExpr(pos);
    
    function add(name, getValue:Option<Type>->Expr, ?panicAt:Position) {
      function panic(message)
        if (panicAt != null) panicAt.error(message);

      if (exists[name]) 
        panic('Duplicate field $name');
      else 
        switch requiredType(name) {
          case Failure(e): 
            panic(e.message);
          case Success(t):
            exists[name] = true;
            fields.push({
              field: name,
              expr: getValue(t)
            });            
        }
    }

    for (f in individual)
      add(f.name, f.getValue, f.pos);

    for (e in complex) {
      
      var t = e.typeof().sure(),
          owner = '__o${args.length}';
      
      callArgs.push(e);

      args.push({
        name: owner,
        type: t.toComplex(),
      });

      for (f in t.getFields().sure()) 
        if (isPublicField(f)) {
          var name = f.name;    
          add(name, function (_) return macro $i{owner}.$name);
        }
    }

    return ret.call(callArgs, pos);    
  }

  static public function isPublicField(c:ClassField) 
    return c.isPublic && c.kind.match(FVar(_, _));

  static public function requiredFields(type:Type)
    return switch type {
      case null: function (_) return Success(None);
      default: 
        var ct = type.toComplex();
        function (name:String)
          return (macro (null : $ct).$name).typeof().map(Some);
    }

  static function parseFilter(e:Expr) 
    return switch e {
      case null | macro null: 
        function (_) return true;
      case macro !$e: 
        var f = parseFilter(e);
        function (x) return !f(x);
      case { expr: EConst(CString(s)) }: 
        s = s.replace('*', '.*');
        new EReg('^$s$', 'i').match;
      case { expr: EConst(CRegexp(pat, flags)) }: 
        new EReg(pat, flags).match;
      default: 
        e.reject('Not a valid filter. Must be a string constant or a regex literal');
    }    

static public function makeSplat(e:Expr, ?prefix:Expr, ?filter:Expr) {
    
    var include = null;
    var prefix = switch prefix.getIdent() {
      case Success('null') | Failure(_):
        include = parseFilter(prefix);
        null;
      case Success(v):
        include = parseFilter(filter);
        v;
    }

    function getName(name:String)
      return 
        if (prefix == null) name;
        else prefix + name.charAt(0).toUpperCase() + name.substr(1);

    var vars = [],
        owner = MacroApi.tempName();

    var ret = EVars(vars).at(e.pos);

    vars.push({
      name: owner,
      expr: e,
      type: null,
    });

    for (f in e.typeof().sure().getFields().sure())
      if (isPublicField(f) && include(f.name)) {
        var field = f.name;
        vars.push({
          name: getName(f.name),
          expr: macro @:pos(e.pos) $i{owner}.$field,
          type: null,
        });
      }

    return ret;
  }    
    
}