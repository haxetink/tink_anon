package tink.anon;

using tink.MacroApi;

class Interface {
  static function build() {
    return tink.macro.BuildCache.getType('tink.anon.Interface', null, null, ctx -> {
      var name = ctx.name;
      var ret = macro class $name {};

      switch ctx.type.reduce() {
        case TAnonymous(_.get() => { fields: fields }):
          for (f in fields)
            ret.fields.push({
              name: f.name,
              doc: f.doc,
              access: if (f.isFinal) [AFinal] else [],
              kind: switch f.kind {
                case FVar(_) if (f.isFinal):
                  FVar(f.type.toComplex());
                case FVar(read, write):

                  FProp(read.accessToName(), read.accessToName(false), f.type.toComplex());

                case FMethod(k):

                  switch f.type.reduce() {
                    case TFun(args, ret):
                      FFun({
                        expr: null,
                        params: switch f.params {
                          case []: [];
                          default: ctx.pos.error('parametrized methods currently not supported');
                        },
                        args: [for (a in args) {
                          name: a.name,
                          opt: a.opt,
                          type: a.t.toComplex(),
                        }],
                        ret: ret.toComplex(),
                      });

                    default: throw 'assert';
                  }
              },
              pos: f.pos,
              meta: f.meta.get(),
            });
        default:
          ctx.pos.error('anonymous structure expected');
      }

      ret.kind = TDClass(null, [], true);

      return ret;
    });
  }
}