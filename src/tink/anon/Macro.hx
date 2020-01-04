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
  var pos(default, null):Position;
  var type(default, null):Lazy<Type>;
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
      fields:RequireFields, ?resolve:String->String,
      ?pos:Position, ?as:ComplexType, ?errors:{
        function unknownField(name:String):String;
        function duplicateField(name:String):String;
        function missingField(name:String):String;
      }
    ) {

    pos = pos.sanitize();

    if (errors == null)
      errors = {
        unknownField: function (name) return 'unknown field $name',
        duplicateField: function (name) return 'duplicate field $name',
        missingField: function (name) return 'missing field $name',
      }

    return switch fields {
      case RStatic(fields):
        var obj:Array<ObjectField> = [],
            vars = [],
            optionals = [],
            defined = new Map(),
            retName = MacroApi.tempName();

        var ret = {
          macro {
            ${EVars(vars).at(pos)};
            var $retName:$as = ${EObjectDecl(obj).at(pos)};
            $b{optionals};
            $i{retName}
          }
        }

        function lookup(field:{ var name(default, null):String; var pos(default, null):Position; }) {
          var name =
            if (resolve == null) field.name;
            else resolve(field.name);

          if (defined[name])
            field.pos.error(errors.duplicateField(name));

          return switch fields[name] {
            case null:
              field.pos.error(errors.unknownField(name));
            case v:
              defined[name] = true;
              v;
          }
        }

        for (p in individual) {
          var info = lookup(p);
          obj.push({ field: info.name, expr: p.getValue(Some(info.type.get())), quotes: p.quotes });
        }

        var complex = [for (o in complex) Lazy.ofFunc(
          function () {
            var ot = o.typeof().sure();
            var getField =
              switch ot.reduce() {
                case TAnonymous(_.get().fields => fields):
                  var m = [for (f in fields) f.name => f];
                  function (name) return m.get(name);
                case TInst(_.get() => cl, _):
                  function (name) return cl.findField(name);
                default:
                  o.reject('currently only supporting anonymous objects');
              }

            var varName = null;

            return function (name:String):Null<Expr> {
              return switch getField(name) {
                case null:
                  null;
                case f:
                  if (varName == null) {
                    var index = complex.indexOf(o);
                    varName = '__o$index';
                    vars.push({
                      name: varName,
                      type: ot.toComplex(), // may be faster without
                      expr: o,
                    });
                  }
                  macro @:pos(f.pos) $i{varName}.$name;
              }
            }
          }
        )];

        for (name in fields.keys()) if (!defined[name]) {
          var field = fields[name];
          for (o in complex)
            switch o.get()(name) {
              case null:
              case value:
                defined[name] = true;
                if (field.optional)
                  optionals.push(macro switch ($value) {
                    case null:
                    case v: untyped $i{retName}.$name = v; //not exactly elegant
                  });
                else
                  obj.push({ field: name, expr: value });
                break;
            }
          if (!(field.optional || defined[name]))
            pos.error(errors.missingField(name));
        }

        vars.sort(function (a, b) return Reflect.compare(a.name, b.name));

        ret;
      case RDynamic(type): // I'm compelled to merge this case with the above somehow, but perhaps they are different enough (the above picks from complex objects by expected fields)
        var defined = new Map(),
            wrap = switch type {
              case null: function (e) return e;
              default: var ct = type.toComplex(); function (e) return macro @:pos(e.pos) ($e : $ct);
            },
            ret = new Array<ObjectField>(),
            vars = new Array<Var>();

        for (p in individual)
          if (defined[p.name])
            p.pos.error(errors.duplicateField(p.name));
          else {
            defined[p.name] = true;
            ret.push({ field: p.name, expr: p.getValue(None), quotes: p.quotes });
          }

        for (o in complex) {
          var ot = typeof(o);
          var fields = switch ot.reduce() {
            case t = TInst(_):
              classFields(t);
            case TAnonymous(a):
              anonFields(a.get());
            default:
              o.reject('type has no fields (${ot.toString()})');
          }
          var varName = null;
          for (f in fields)
            if (!defined[f.name]) {
              defined[f.name] = true;
              if (varName == null) {
                varName = '__o${vars.length}';
                vars.push({
                  name: varName,
                  type: null,
                  expr: o
                });
              }
              ret.push({ field: f.name, expr: macro $p{[varName, f.name]} });
            }
        }

        var ret = EObjectDecl(ret).at(pos);
        if (as != null)
          ret = ret.as(as);

        return [EVars(vars).at(pos), ret].toBlock();
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
        pos: f.pos,
        optional: f.meta.has(':optional'),
        type: f.type
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
          pos: f.pos,
          optional: f.meta.has(':optional'),
          type: function () return typeof(sample.get().field(f.name)),
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