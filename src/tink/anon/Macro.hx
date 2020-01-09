package tink.anon;

#if macro
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
  function getValue(expected:Option<Type>):Expr;
  @:optional var quotes(default, null):QuoteStatus;
}

enum RequireFields {
  RStatic(fields:Map<String, FieldInfo>);
  RDynamic(?type:Type);
}

typedef FieldInfo = {
  var optional(default, null):Bool;
  var name(default, null):String;
  var type(default, null):Lazy<Option<Type>>;
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

  static public function mergeExpressions(exprs:Array<Expr>, fields, ?pos, ?as) {
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

    return mergeParts(individual, complex, fields, null, pos, as);
  }

  static public function mergeParts(
      individual:Array<Part>, complex:Array<Expr>,
      fields:RequireFields, ?resolveAlias:String->String,
      ?pos:Position, ?as:ComplexType, ?errors:{
        function unknownField(name:Part):Outcome<FieldInfo, String>;
        function duplicateField(name:String):String;
        function missingField(field:FieldInfo):String;
      }
    ) {

    pos = pos.sanitize();

    if (errors == null)
      errors = {
        unknownField: function (part) return Failure('unknown field ${part.name}'),
        duplicateField: function (name) return 'duplicate field $name',
        missingField: function (f) return 'missing field ${f.name}',
      }

    inline function resolve(o)
      return
        if (resolveAlias != null) resolveAlias(o.name);
        else o.name;

        var obj:Array<ObjectField> = [],
        vars:Array<Var> = [],
        optionals:Array<Expr> = [],
        defined = new Map(),
        retName = MacroApi.tempName();

    var getField = switch fields {
      case RStatic(fields):
        function (name) return fields.get(name);
      case RDynamic(t):
        var t:Lazy<Option<Type>> = switch t {
          case null: None;
          default: Some(t);
        }
        function (name) return {
          optional: false,
          name: name,
          type: t,
        }
    }

    var ret = EObjectDecl(obj).at(pos);
    if (as != null)
      ret = ret.as(as);

    for (p in individual) {

      var name = resolve(p);

      if (defined[name])
        p.pos.error(errors.duplicateField(name));

      defined[name] = true;

      var info = switch getField(name) {
        case null:
          switch errors.unknownField(p) {
            case Success(v): v;
            case Failure(e): p.pos.error(e);
          }
        case v:
          v;
      }

      obj.push({ field: info.name, expr: p.getValue(info.type.get()), quotes: p.quotes });
    }

    for (o in complex) {
      var ot = typeof(o);
      var given = switch ot.reduce() {
        case t = TInst(_):
          classFields(t);
        case TAnonymous(a):
          anonFields(a.get());
        default:
          o.reject('type has no fields (${ot.toString()})');
      }

      var varName = null;
      for (found in given) {
        var name = resolve(found);

        if (!defined[name])
          switch getField(name) {
            case null:
            case { optional: optional }:
              defined[name] = true;
              if (varName == null) {
                varName = '__o${vars.length}';
                vars.push({
                  name: varName,
                  type: null,
                  expr: o
                });
              }

              var value = macro @:pos(o.pos) $p{[varName, found.name]};

              if (optional)
                optionals.push(macro switch ($value) {
                  case null:
                  case v: untyped $i{retName}.$name = v; //not exactly elegant
                });
              else
                obj.push({ field: name, expr: value });
          }
      }
    }

    switch fields {
      case RStatic(fields):
        for (f in fields)
          if (!(defined[f.name] || f.optional))
            pos.error(errors.missingField(f));
      default:
    }

    if (optionals.length > 0) {
      optionals.unshift(macro @:pos(pos) var $retName = $ret);
      optionals.push(macro @:pos(pos) $i{retName});
      ret = optionals.toBlock();
    }

    return switch vars {
      case []: ret;
      default:
        EVars(vars).at(pos).concat(ret);
    }
  }

  static public function drillAbstracts(type:Type) {
    function drill(type:haxe.macro.Type):Option<haxe.macro.Type> {
      return
        if(type == null)
          None;
        else switch type.reduce() {
          case t = TAbstract(_.get() => {from: types, params: params}, concrete):
            for(type in types)
              switch drill(haxe.macro.TypeTools.applyTypeParameters(type.t, params, concrete)) {
                case Some(t): return Some(t);
                case _: // try next
              }
            None;
          case t = TAnonymous(_): Some(t);
          case _: None;
        }
    }

    return return drill(type).or(type);
  }

  static public function isPublicField(c:ClassField, ?isExtern:Bool)
    return switch c.kind {
      case FMethod(_) if (isExtern): false;
      case FMethod(MethMacro): false;
      case FMethod(MethInline) if (c.meta.has(':extern')): false;
      default: c.isPublic;
    }

  static public function requiredFields(type:Type, ?pos:Position):RequireFields
    return
      if (type == null) RDynamic();
      else switch type.reduce() {
        case TDynamic(t): RDynamic(t);
        case TMono(_.get() => null): RDynamic();
        case TAnonymous(a):
          RStatic(anonFields(a.get()));
        case TInst(_.get() => cl, _) if (!cl.isInterface && cl.meta.has(':structInit')):
          RStatic(classFields(type, cl));
        case v:
          pos.error('expected type should be struct or @:structInit');
      }

  static function anonFields(a:AnonType)
    return [for (f in a.fields)
      f.name => ({
        name: f.name,
        // pos: f.pos,
        optional: f.meta.has(':optional'),
        type: Some(f.type)
      }:FieldInfo)
    ];

  static function classFields(type:Type, ?cl:ClassType, ?include) {
    if (cl == null)
      cl = switch type {
        case TInst(_.get() => cl, _): cl;
        default: throw 'assert';
      }

    if (include == null)
      include = function (f) return isPublicField(f, cl.isExtern);

    var ret = new Map(),
        sample = Lazy.ofFunc(function () {
          var ct = type.toComplex();
          return macro (cast null : $ct);
        });

    function crawl(cl:ClassType) {
      for (f in cl.fields.get()) if (include(f))
        ret[f.name] = ({
          name: f.name,
          optional: f.meta.has(':optional'),
          type: function () return Some(typeof(sample.get().field(f.name))),
        }:FieldInfo);
      switch cl.superClass {
        case null:
        case v: crawl(v.t.get());
      }
    }

    crawl(cl);
    return ret;
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
#end