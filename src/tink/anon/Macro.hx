package tink.anon;

#if !macro
  #error
#end
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.macro.BuildCache;

using StringTools;
using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

typedef Part = { 
  var name(default, null):String;
  var pos(default, null):Position;
  var getValue(default, null):Option<Type>->Expr;
  @:optional var quotes(default, null):QuoteStatus;
}

abstract FieldInfo({ optional:Bool, type: Type }) {

  public var optional(get, never):Bool;
    inline function get_optional() return this.optional;

  public var type(get, never):Type;
    inline function get_type() return this.type;

  public inline function new(o) this = o;
  @:from static function ofType(type:Type)
    return new FieldInfo({ optional: false, type: type });
  @:from static function ofClassField(f:ClassField)
    return new FieldInfo({ optional: f.meta.has(':optional'), type: f.type });
}

class Macro {
  
  static public function buildReadOnly() {
    return BuildCache.getType('tink.anon.ReadOnly', function(ctx) {
      var name = ctx.name;
      var ct = ctx.type.toComplex();
      var def = macro class $name {};
      function add(c:TypeDefinition) def.fields = def.fields.concat(c.fields);
      
      switch ctx.type.reduce() {
        case TAnonymous(_.get() => {fields: fields}):
          for(field in fields) {
            var fname = field.name;
            var ct = field.type.toComplex();
            if(field.type.reduce().match(TAnonymous(_))) ct = macro:tink.anon.ReadOnly<$ct>;
            add(macro class {
              var $fname(default, never):$ct;
            });
          }
        default:
          ctx.pos.error('Only supports anonymous structures');
      }
      
      def.pack = ['tink', 'anon'];
      def.kind = TDStructure;
      return def;
    });
  }
  
  static public function mergeExpressions(exprs:Array<Expr>, ?findField, ?pos, ?as) {
    var complex = [],
        individual:Array<Part> = [];

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
    
    return mergeParts(individual, complex, findField, function (name) return name, pos, as);
  }

  static public function mergeParts(
    individual:Array<Part>, 
    complex:Array<Expr>,
    ?findField:String->Outcome<Option<FieldInfo>, Error>,
    ?resolve:String->String, 
    ?pos:Position, 
    ?as:ComplexType
  ) {
    var fields:Array<ObjectField> = [],
        args = [],
        callArgs = [],
        exists = new Map(),
        optional = [],
        pos = pos.sanitize();

    if (findField == null)
      findField = function (_) return Success(None);

    var ret = EObjectDecl(fields).at(pos);

    if (as != null) 
      ret = macro @:pos(pos) ($ret:$as);

    ret = macro @:pos(pos) {
      var __ret = $ret;
      $b{optional};
      return __ret;
    }
    ret = ret.func(args, false).asExpr(pos);  
    
    function add(name, getValue:Option<Type>->Expr, sourceOptional:Bool, ?panicAt:Position, ?quotes) {
      
      if (resolve != null)
        name = resolve(name);

      function panic(message)
        if (panicAt != null) panicAt.error(message);

      if (exists[name]) 
        panic('Duplicate field $name');
      else 
        switch findField(name) {
          case Failure(e): 
            panic(e.message);
          case Success(t):
            exists[name] = true;
            var value = getValue(t.map(function (f) return f.type));
            if (sourceOptional && t.match(Some({ optional: true })))
              optional.push(macro @:pos(value.pos) switch ($value) {
                case null: 
                case v: untyped __ret.$name = v;//TODO: this is not exactly elegant
              });
            else
              fields.push({
                field: name,
                expr: value,
                quotes: quotes,
              });            
        }
    }

    for (f in individual)
      add(f.name, f.getValue, false, f.pos, f.quotes);

    var isPrivateVisible = 
      switch getLocalType() {
        case TInst(_.get() => cl, _):
          function (f:ClassField)
            return switch cl.findField(f.name) {
              case null: false;
              case l: Std.string(l.pos) == Std.string(f.pos);
            }
        default: function (_) return false;
      }

    for (e in complex) {
      
      var t = e.typeof().sure(),
          owner = '__o${args.length}';
      
      callArgs.push(e);

      args.push({
        name: owner,
        type: t.toComplex(),
      });

      var isExtern = switch t {
        case TInst(_.get().isExtern => v, _): v;
        default: false;
      }

      for (f in t.getFields().sure()) 
        if (isPrivateVisible(f) || isPublicField(f, isExtern)) {
          var name = f.name;    
          add(name, function (_) return macro @:pos(f.pos) $i{owner}.$name, f.meta.has(':optional'));
        }
    }

    return ret.call(callArgs, pos);    
  }

  static public function isPublicField(c:ClassField, ?isExtern:Bool) 
    return switch c.kind {
      case FMethod(_) if (isExtern): false;
      case FMethod(MethMacro): false;
      case FMethod(MethInline) if (c.meta.has(':extern')): false;
      default: c.isPublic;
    }

  static public function requiredFields(type:Type)
    return switch type {
      case null: function (_) return Success(None);
      default: 
        var ct = type.toComplex();
        var isOptional = switch type.getFields(false) {
          case Success(f): 
            var optional = [for (f in f) f.name => f.meta.has(':optional')];
            function (name) return optional[name];
          default: function (_) return false;
        }
        function (name:String)
          return 
            (macro (null : $ct).$name).typeof()
              .map(function (t) return Some(new FieldInfo({
                type: t,
                optional: isOptional(name),
              })));
    }

  static function parseFilter(e:Expr) 
    return switch e {
      case null | macro null: 
        function (_) return true;
      case macro !$e: 
        var f = parseFilter(e);
        function (x) return !f(x);
      case { expr: EArrayDecl(_.map(parseFilter) => filters) }:
        return function (s) {
          for (f in filters) if (f(s)) return true;
          return false;
        }
      case macro $i{ident}:
        return function (s) return s == ident;
      case { expr: EConst(CString(s)) }: 
        s = s.replace('*', '.*');
        new EReg('^($s)$', 'i').match;
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
