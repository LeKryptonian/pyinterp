#import "../include/Interpreter.h"
#import <math.h>

// ── Signals ──────────────────────────────────────────────────────────────────
@interface BreakSignal : NSException @end
@implementation BreakSignal @end
@interface ContinueSignal : NSException @end
@implementation ContinueSignal @end
@interface ReturnSignal : NSException
@property (strong) PyObject *value;
- (instancetype)initWithValue:(PyObject *)v;
@end
@implementation ReturnSignal
- (instancetype)initWithValue:(PyObject *)v { self=[super initWithName:@"Return" reason:nil userInfo:nil]; _value=v; return self; }
@end

// ── PyObject ─────────────────────────────────────────────────────────────────
@implementation PyObject
+ (instancetype)withInt:(long long)v   { PyObject *o=[[self alloc]init]; o.type=@"int";   o.value=@(v); return o; }
+ (instancetype)withFloat:(double)v    { PyObject *o=[[self alloc]init]; o.type=@"float"; o.value=@(v); return o; }
+ (instancetype)withString:(NSString *)v { PyObject *o=[[self alloc]init]; o.type=@"str";   o.value=v;   return o; }
+ (instancetype)withBool:(BOOL)v       { PyObject *o=[[self alloc]init]; o.type=@"bool";  o.value=@(v); return o; }
+ (instancetype)none                   { PyObject *o=[[self alloc]init]; o.type=@"none";  o.value=[NSNull null]; return o; }
+ (instancetype)withList:(NSMutableArray *)v  { PyObject *o=[[self alloc]init]; o.type=@"list";  o.value=v; return o; }
+ (instancetype)withDict:(NSMutableDictionary *)v { PyObject *o=[[self alloc]init]; o.type=@"dict"; o.value=v; return o; }

- (NSString *)repr {
    if ([_type isEqualToString:@"none"])  return @"None";
    if ([_type isEqualToString:@"bool"])  return [(NSNumber *)_value boolValue] ? @"True" : @"False";
    if ([_type isEqualToString:@"int"])   return [NSString stringWithFormat:@"%lld", [(NSNumber *)_value longLongValue]];
    if ([_type isEqualToString:@"float"]) {
        double d = [(NSNumber *)_value doubleValue];
        if (d == (long long)d) return [NSString stringWithFormat:@"%.1f", d];
        return [NSString stringWithFormat:@"%g", d];
    }
    if ([_type isEqualToString:@"str"])   return (NSString *)_value;
    if ([_type isEqualToString:@"list"] || [_type isEqualToString:@"tuple"]) {
        NSMutableString *s = [NSMutableString stringWithString:[_type isEqualToString:@"tuple"] ? @"(" : @"["];
        NSMutableArray *items = (NSMutableArray *)_value;
        for (NSUInteger i=0;i<items.count;i++) {
            if (i) [s appendString:@", "];
            PyObject *item = items[i];
            if ([item.type isEqualToString:@"str"]) [s appendFormat:@"'%@'", [item repr]];
            else [s appendString:[item repr]];
        }
        [s appendString:[_type isEqualToString:@"tuple"] ? @")" : @"]"];
        return s;
    }
    if ([_type isEqualToString:@"dict"]) {
        NSMutableString *s = [NSMutableString stringWithString:@"{"];
        NSMutableDictionary *d = (NSMutableDictionary *)_value;
        BOOL first = YES;
        for (NSString *k in d) {
            if (!first) [s appendString:@", "]; first=NO;
            PyObject *kobj = d[k];
            (void)kobj;
            [s appendFormat:@"'%@': %@", k, [(PyObject *)d[k] repr]];
        }
        [s appendString:@"}"];
        return s;
    }
    if ([_type isEqualToString:@"func"])  return [NSString stringWithFormat:@"<function %@>", [_value[@"name"] repr] ?: @"?"];
    if ([_type isEqualToString:@"builtin"]) return [NSString stringWithFormat:@"<built-in function>"];
    if ([_type isEqualToString:@"class"]) return [NSString stringWithFormat:@"<class '%@'>", _value[@"name"]];
    if ([_type isEqualToString:@"instance"]) return [NSString stringWithFormat:@"<%@ object>", _value[@"class"]];
    return [NSString stringWithFormat:@"<object type=%@>", _type];
}

- (BOOL)isTruthy {
    if ([_type isEqualToString:@"none"])  return NO;
    if ([_type isEqualToString:@"bool"])  return [(NSNumber *)_value boolValue];
    if ([_type isEqualToString:@"int"])   return [(NSNumber *)_value longLongValue] != 0;
    if ([_type isEqualToString:@"float"]) return [(NSNumber *)_value doubleValue] != 0.0;
    if ([_type isEqualToString:@"str"])   return [(NSString *)_value length] > 0;
    if ([_type isEqualToString:@"list"])  return [(NSMutableArray *)_value count] > 0;
    if ([_type isEqualToString:@"dict"])  return [(NSMutableDictionary *)_value count] > 0;
    return YES;
}
@end

// ── Environment ──────────────────────────────────────────────────────────────
@interface Environment ()
@property NSMutableDictionary<NSString *, PyObject *> *vars;
@end

@implementation Environment
- (instancetype)initWithParent:(Environment *)parent {
    self=[super init]; _parent=parent; _vars=[NSMutableDictionary dictionary]; return self;
}
- (PyObject *)get:(NSString *)name {
    PyObject *v = _vars[name];
    if (v) return v;
    if (_parent) return [_parent get:name];
    return nil;
}
- (void)set:(NSString *)name value:(PyObject *)value {
    // Walk up to find the binding, or set in local
    Environment *env = self;
    while (env) {
        if (env.vars[name]) { env.vars[name] = value; return; }
        env = env.parent;
    }
    _vars[name] = value;
}
- (void)setLocal:(NSString *)name value:(PyObject *)value { _vars[name] = value; }
- (BOOL)has:(NSString *)name { return _vars[name] != nil || (_parent && [_parent has:name]); }
@end

// ── Interpreter ──────────────────────────────────────────────────────────────
@interface Interpreter ()
@property Environment *globalEnv;
@end

@implementation Interpreter

- (instancetype)init {
    self=[super init];
    _globalEnv = [[Environment alloc] initWithParent:nil];
    [self setupBuiltins];
    return self;
}

- (void)setupBuiltins {
    // len
    PyObject *lenFn = [[PyObject alloc] init]; lenFn.type = @"builtin";
    lenFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject;
        if (!a) return [PyObject withInt:0];
        if ([a.type isEqualToString:@"list"] || [a.type isEqualToString:@"tuple"])
            return [PyObject withInt:[(NSMutableArray *)a.value count]];
        if ([a.type isEqualToString:@"str"])
            return [PyObject withInt:[(NSString *)a.value length]];
        if ([a.type isEqualToString:@"dict"])
            return [PyObject withInt:[(NSMutableDictionary *)a.value count]];
        return [PyObject withInt:0];
    };
    [_globalEnv setLocal:@"len" value:lenFn];

    // range
    PyObject *rangeFn = [[PyObject alloc] init]; rangeFn.type = @"builtin";
    rangeFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        long long start=0, stop=0, step=1;
        if (args.count==1) { stop=[(NSNumber *)((PyObject *)args[0]).value longLongValue]; }
        else if (args.count>=2) {
            start=[(NSNumber *)((PyObject *)args[0]).value longLongValue];
            stop=[(NSNumber *)((PyObject *)args[1]).value longLongValue];
            if (args.count>=3) step=[(NSNumber *)((PyObject *)args[2]).value longLongValue];
        }
        NSMutableArray *lst = [NSMutableArray array];
        if (step>0) for (long long i=start;i<stop;i+=step) [lst addObject:[PyObject withInt:i]];
        else        for (long long i=start;i>stop;i+=step) [lst addObject:[PyObject withInt:i]];
        return [PyObject withList:lst];
    };
    [_globalEnv setLocal:@"range" value:rangeFn];

    // int, float, str, bool
    PyObject *intFn = [[PyObject alloc] init]; intFn.type = @"builtin";
    intFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (!args.count) return [PyObject withInt:0];
        PyObject *a = args[0];
        if ([a.type isEqualToString:@"str"]) return [PyObject withInt:[(NSString *)a.value longLongValue]];
        if ([a.type isEqualToString:@"float"]) return [PyObject withInt:(long long)[(NSNumber *)a.value doubleValue]];
        if ([a.type isEqualToString:@"bool"]) return [PyObject withInt:[(NSNumber *)a.value boolValue] ? 1 : 0];
        return a;
    };
    [_globalEnv setLocal:@"int" value:intFn];

    PyObject *floatFn = [[PyObject alloc] init]; floatFn.type = @"builtin";
    floatFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (!args.count) return [PyObject withFloat:0.0];
        PyObject *a = args[0];
        if ([a.type isEqualToString:@"str"]) return [PyObject withFloat:[(NSString *)a.value doubleValue]];
        if ([a.type isEqualToString:@"int"] || [a.type isEqualToString:@"bool"])
            return [PyObject withFloat:[(NSNumber *)a.value doubleValue]];
        return a;
    };
    [_globalEnv setLocal:@"float" value:floatFn];

    PyObject *strFn = [[PyObject alloc] init]; strFn.type = @"builtin";
    strFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (!args.count) return [PyObject withString:@""];
        return [PyObject withString:[(PyObject *)args[0] repr]];
    };
    [_globalEnv setLocal:@"str" value:strFn];

    PyObject *boolFn = [[PyObject alloc] init]; boolFn.type = @"builtin";
    boolFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (!args.count) return [PyObject withBool:NO];
        return [PyObject withBool:[(PyObject *)args[0] isTruthy]];
    };
    [_globalEnv setLocal:@"bool" value:boolFn];

    // abs
    PyObject *absFn = [[PyObject alloc] init]; absFn.type = @"builtin";
    absFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject;
        if ([a.type isEqualToString:@"int"]) return [PyObject withInt:llabs([(NSNumber *)a.value longLongValue])];
        return [PyObject withFloat:fabs([(NSNumber *)a.value doubleValue])];
    };
    [_globalEnv setLocal:@"abs" value:absFn];

    // max, min
    PyObject *maxFn = [[PyObject alloc] init]; maxFn.type = @"builtin";
    maxFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        NSArray *lst = args;
        if (args.count==1 && [((PyObject *)args[0]).type isEqualToString:@"list"])
            lst = ((PyObject *)args[0]).value;
        PyObject *best = lst.firstObject;
        for (PyObject *o in lst) {
            double ov = [(NSNumber *)o.value doubleValue];
            if (ov > [(NSNumber *)best.value doubleValue]) best=o;
        }
        return best ?: [PyObject none];
    };
    [_globalEnv setLocal:@"max" value:maxFn];

    PyObject *minFn = [[PyObject alloc] init]; minFn.type = @"builtin";
    minFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        NSArray *lst = args;
        if (args.count==1 && [((PyObject *)args[0]).type isEqualToString:@"list"])
            lst = ((PyObject *)args[0]).value;
        PyObject *best = lst.firstObject;
        for (PyObject *o in lst) {
            double ov = [(NSNumber *)o.value doubleValue];
            if (ov < [(NSNumber *)best.value doubleValue]) best=o;
        }
        return best ?: [PyObject none];
    };
    [_globalEnv setLocal:@"min" value:minFn];

    // sum
    PyObject *sumFn = [[PyObject alloc] init]; sumFn.type = @"builtin";
    sumFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject;
        NSArray *lst = [a.type isEqualToString:@"list"] ? (NSArray *)a.value : args;
        long long s=0; BOOL isFloat=NO; double sf=0;
        for (PyObject *o in lst) {
            if ([o.type isEqualToString:@"float"]) { isFloat=YES; sf+=[(NSNumber *)o.value doubleValue]; }
            else s+=[(NSNumber *)o.value longLongValue];
        }
        if (isFloat) return [PyObject withFloat:sf+s];
        return [PyObject withInt:s];
    };
    [_globalEnv setLocal:@"sum" value:sumFn];

    // type
    PyObject *typeFn = [[PyObject alloc] init]; typeFn.type = @"builtin";
    typeFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject;
        if (!a) return [PyObject withString:@"<class 'NoneType'>"];
        return [PyObject withString:[NSString stringWithFormat:@"<class '%@'>", a.type]];
    };
    [_globalEnv setLocal:@"type" value:typeFn];

    // isinstance
    PyObject *isinstanceFn = [[PyObject alloc] init]; isinstanceFn.type = @"builtin";
    isinstanceFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (args.count<2) return [PyObject withBool:NO];
        PyObject *obj = args[0]; PyObject *cls = args[1];
        if ([cls.type isEqualToString:@"str"]) {
            return [PyObject withBool:[obj.type isEqualToString:(NSString *)cls.value]];
        }
        return [PyObject withBool:NO];
    };
    [_globalEnv setLocal:@"isinstance" value:isinstanceFn];

    // input
    PyObject *inputFn = [[PyObject alloc] init]; inputFn.type = @"builtin";
    inputFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (args.count) printf("%s", [(PyObject *)args[0] repr].UTF8String);
        char buf[1024]; fgets(buf, sizeof(buf), stdin);
        NSString *s = [NSString stringWithUTF8String:buf];
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        return [PyObject withString:s];
    };
    [_globalEnv setLocal:@"input" value:inputFn];

    // sorted
    PyObject *sortedFn = [[PyObject alloc] init]; sortedFn.type = @"builtin";
    sortedFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject;
        NSMutableArray *lst = [NSMutableArray arrayWithArray:(NSArray *)a.value];
        BOOL rev = [(NSNumber *)kwargs[@"reverse"] boolValue];
        [lst sortUsingComparator:^NSComparisonResult(PyObject *x, PyObject *y) {
            double xv, yv;
            if ([x.type isEqualToString:@"str"] && [y.type isEqualToString:@"str"])
                return rev ? [(NSString *)y.value compare:(NSString *)x.value] : [(NSString *)x.value compare:(NSString *)y.value];
            xv=[(NSNumber *)x.value doubleValue]; yv=[(NSNumber *)y.value doubleValue];
            NSComparisonResult r = xv<yv ? NSOrderedAscending : xv>yv ? NSOrderedDescending : NSOrderedSame;
            return rev ? -r : r;
        }];
        return [PyObject withList:lst];
    };
    [_globalEnv setLocal:@"sorted" value:sortedFn];

    // enumerate
    PyObject *enumFn = [[PyObject alloc] init]; enumFn.type = @"builtin";
    enumFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        PyObject *a = args.firstObject; NSMutableArray *result = [NSMutableArray array];
        NSArray *lst = (NSArray *)a.value;
        for (NSUInteger i=0;i<lst.count;i++) {
            NSMutableArray *pair = [NSMutableArray arrayWithObjects:[PyObject withInt:i], lst[i], nil];
            [result addObject:[PyObject withList:pair]];
        }
        return [PyObject withList:result];
    };
    [_globalEnv setLocal:@"enumerate" value:enumFn];

    // zip
    PyObject *zipFn = [[PyObject alloc] init]; zipFn.type = @"builtin";
    zipFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (args.count==0) return [PyObject withList:[NSMutableArray array]];
        NSUInteger minLen = NSUIntegerMax;
        for (PyObject *a in args) minLen = MIN(minLen, [(NSArray *)a.value count]);
        NSMutableArray *result = [NSMutableArray array];
        for (NSUInteger i=0;i<minLen;i++) {
            NSMutableArray *tup = [NSMutableArray array];
            for (PyObject *a in args) [tup addObject:((NSArray *)a.value)[i]];
            [result addObject:[PyObject withList:tup]];
        }
        return [PyObject withList:result];
    };
    [_globalEnv setLocal:@"zip" value:zipFn];

    // list, dict
    PyObject *listFn = [[PyObject alloc] init]; listFn.type = @"builtin";
    listFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        if (!args.count) return [PyObject withList:[NSMutableArray array]];
        PyObject *a = args[0];
        if ([a.type isEqualToString:@"list"]) return [PyObject withList:[NSMutableArray arrayWithArray:(NSArray *)a.value]];
        return [PyObject withList:[NSMutableArray arrayWithObject:a]];
    };
    [_globalEnv setLocal:@"list" value:listFn];

    PyObject *dictFn = [[PyObject alloc] init]; dictFn.type = @"builtin";
    dictFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        return [PyObject withDict:[NSMutableDictionary dictionary]];
    };
    [_globalEnv setLocal:@"dict" value:dictFn];

    // print is handled as a statement but also register as builtin
    PyObject *printFn = [[PyObject alloc] init]; printFn.type = @"builtin";
    printFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        NSMutableArray *parts = [NSMutableArray array];
        for (PyObject *a in args) [parts addObject:[a repr]];
        NSString *sep = kwargs[@"sep"] ? [(PyObject *)kwargs[@"sep"] repr] : @" ";
        NSString *end = kwargs[@"end"] ? [(PyObject *)kwargs[@"end"] repr] : @"\n";
        printf("%s%s", [[parts componentsJoinedByString:sep] UTF8String], end.UTF8String);
        return [PyObject none];
    };
    [_globalEnv setLocal:@"print" value:printFn];

    // math module placeholder
    PyObject *mathMod = [[PyObject alloc] init]; mathMod.type = @"module";
    mathMod.attrs = [NSMutableDictionary dictionary];

    PyObject *sqrtFn = [[PyObject alloc] init]; sqrtFn.type = @"builtin";
    sqrtFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        double v = [(NSNumber *)((PyObject *)args[0]).value doubleValue];
        return [PyObject withFloat:sqrt(v)];
    };
    mathMod.attrs[@"sqrt"] = sqrtFn;

    PyObject *powFn = [[PyObject alloc] init]; powFn.type = @"builtin";
    powFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        double a=[(NSNumber *)((PyObject *)args[0]).value doubleValue];
        double b=[(NSNumber *)((PyObject *)args[1]).value doubleValue];
        return [PyObject withFloat:pow(a,b)];
    };
    mathMod.attrs[@"pow"] = powFn;
    mathMod.attrs[@"pi"] = [PyObject withFloat:M_PI];
    mathMod.attrs[@"e"]  = [PyObject withFloat:M_E];

    PyObject *floorFn = [[PyObject alloc] init]; floorFn.type = @"builtin";
    floorFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        return [PyObject withInt:(long long)floor([(NSNumber *)((PyObject *)args[0]).value doubleValue])];
    };
    mathMod.attrs[@"floor"] = floorFn;

    PyObject *ceilFn = [[PyObject alloc] init]; ceilFn.type = @"builtin";
    ceilFn.value = ^PyObject *(NSArray *args, NSDictionary *kwargs) {
        return [PyObject withInt:(long long)ceil([(NSNumber *)((PyObject *)args[0]).value doubleValue])];
    };
    mathMod.attrs[@"ceil"] = ceilFn;

    [_globalEnv setLocal:@"math" value:mathMod];
}

- (void)runStatements:(NSArray<ASTNode *> *)stmts {
    [self execBlock:stmts inEnv:_globalEnv];
}

- (void)execBlock:(NSArray<ASTNode *> *)stmts inEnv:(Environment *)env {
    for (ASTNode *s in stmts) {
        [self execStmt:s inEnv:env];
    }
}

- (void)execStmt:(ASTNode *)node inEnv:(Environment *)env {
    switch (node.type) {
        case NODE_PASS: break;
        case NODE_BREAK: @throw [BreakSignal exceptionWithName:@"break" reason:nil userInfo:nil];
        case NODE_CONTINUE: @throw [ContinueSignal exceptionWithName:@"continue" reason:nil userInfo:nil];

        case NODE_ASSIGN: {
            PyObject *val = [self evalExpr:[node fieldForKey:@"value"] inEnv:env];
            [self assign:[node fieldForKey:@"target"] value:val inEnv:env];
            break;
        }
        case NODE_AUGASSIGN: {
            ASTNode *target = [node fieldForKey:@"target"];
            NSString *op = [node fieldForKey:@"op"];
            PyObject *cur = [self evalExpr:target inEnv:env];
            PyObject *rhs = [self evalExpr:[node fieldForKey:@"value"] inEnv:env];
            PyObject *result = [self applyBinOp:op left:cur right:rhs];
            [self assign:target value:result inEnv:env];
            break;
        }
        case NODE_PRINT: {
            NSArray *args = [node fieldForKey:@"args"];
            NSMutableArray *parts = [NSMutableArray array];
            for (ASTNode *a in args) [parts addObject:[[self evalExpr:a inEnv:env] repr]];
            printf("%s\n", [[parts componentsJoinedByString:@" "] UTF8String]);
            break;
        }
        case NODE_IF: {
            PyObject *test = [self evalExpr:[node fieldForKey:@"test"] inEnv:env];
            if ([test isTruthy]) {
                [self execBlock:[node fieldForKey:@"body"] inEnv:env];
            } else {
                BOOL done = NO;
                for (ASTNode *elif in (NSArray *)[node fieldForKey:@"elifs"]) {
                    PyObject *etest = [self evalExpr:[elif fieldForKey:@"test"] inEnv:env];
                    if ([etest isTruthy]) {
                        [self execBlock:[elif fieldForKey:@"body"] inEnv:env];
                        done = YES; break;
                    }
                }
                if (!done && [node fieldForKey:@"else"]) {
                    ASTNode *elseNode = [node fieldForKey:@"else"];
                    [self execBlock:[elseNode fieldForKey:@"stmts"] inEnv:env];
                }
            }
            break;
        }
        case NODE_WHILE: {
            while ([[self evalExpr:[node fieldForKey:@"test"] inEnv:env] isTruthy]) {
                @try { [self execBlock:[node fieldForKey:@"body"] inEnv:env]; }
                @catch (BreakSignal *b) { break; }
                @catch (ContinueSignal *c) { continue; }
            }
            break;
        }
        case NODE_FOR: {
            PyObject *iter = [self evalExpr:[node fieldForKey:@"iter"] inEnv:env];
            NSArray *lst = (NSArray *)iter.value;
            NSArray *targets = [node fieldForKey:@"targets"];
            for (PyObject *item in lst) {
                if (targets.count == 1) {
                    [env setLocal:targets[0] value:item];
                } else {
                    NSArray *items = [item.type isEqualToString:@"list"] ? (NSArray *)item.value : @[item];
                    for (NSUInteger i=0;i<targets.count&&i<items.count;i++)
                        [env setLocal:targets[i] value:items[i]];
                }
                @try { [self execBlock:[node fieldForKey:@"body"] inEnv:env]; }
                @catch (BreakSignal *b) { break; }
                @catch (ContinueSignal *c) { continue; }
            }
            break;
        }
        case NODE_FUNCDEF: {
            NSString *name = [node fieldForKey:@"name"];
            PyObject *fn = [[PyObject alloc] init]; fn.type = @"func";
            fn.value = @{ @"name": [PyObject withString:name],
                          @"params": [node fieldForKey:@"params"],
                          @"defaults": [node fieldForKey:@"defaults"],
                          @"body": [node fieldForKey:@"body"],
                          @"closure": env };
            [env setLocal:name value:fn];
            break;
        }
        case NODE_CLASS: {
            NSString *name = [node fieldForKey:@"name"];
            PyObject *cls = [[PyObject alloc] init]; cls.type = @"class";
            NSMutableDictionary *clsDict = [NSMutableDictionary dictionary];
            clsDict[@"name"] = name;
            clsDict[@"bases"] = [node fieldForKey:@"bases"] ?: @[];
            // Execute body in a temp env to capture methods
            Environment *clsEnv = [[Environment alloc] initWithParent:env];
            [self execBlock:[node fieldForKey:@"body"] inEnv:clsEnv];
            clsDict[@"methods"] = clsEnv.vars;
            cls.value = clsDict;
            [env setLocal:name value:cls];
            break;
        }
        case NODE_RETURN: {
            PyObject *val = [node fieldForKey:@"value"] ? [self evalExpr:[node fieldForKey:@"value"] inEnv:env] : [PyObject none];
            @throw [[ReturnSignal alloc] initWithValue:val];
        }
        case NODE_IMPORT: break; // stub
        default:
            // Expression statement
            [self evalExpr:node inEnv:env];
            break;
    }
}

- (void)assign:(ASTNode *)target value:(PyObject *)value inEnv:(Environment *)env {
    if (target.type == NODE_IDENTIFIER) {
        [env setLocal:[target fieldForKey:@"name"] value:value];
    } else if (target.type == NODE_SUBSCRIPT) {
        PyObject *obj = [self evalExpr:[target fieldForKey:@"value"] inEnv:env];
        PyObject *idx = [self evalExpr:[target fieldForKey:@"index"] inEnv:env];
        if ([obj.type isEqualToString:@"list"]) {
            long long i = [(NSNumber *)idx.value longLongValue];
            NSMutableArray *arr = (NSMutableArray *)obj.value;
            if (i < 0) i += arr.count;
            [arr replaceObjectAtIndex:(NSUInteger)i withObject:value];
        } else if ([obj.type isEqualToString:@"dict"]) {
            ((NSMutableDictionary *)obj.value)[[idx repr]] = value;
        }
    } else if (target.type == NODE_ATTRIBUTE) {
        PyObject *obj = [self evalExpr:[target fieldForKey:@"value"] inEnv:env];
        NSString *attr = [target fieldForKey:@"attr"];
        if (!obj.attrs) obj.attrs = [NSMutableDictionary dictionary];
        obj.attrs[attr] = value;
    }
}

- (PyObject *)evalExpr:(ASTNode *)node inEnv:(Environment *)env {
    if (!node) return [PyObject none];
    switch (node.type) {
        case NODE_NUMBER: {
            NSString *v = [node fieldForKey:@"value"];
            if ([v containsString:@"."] || [v containsString:@"e"] || [v containsString:@"E"])
                return [PyObject withFloat:[v doubleValue]];
            return [PyObject withInt:[v longLongValue]];
        }
        case NODE_STRING: return [PyObject withString:[node fieldForKey:@"value"]];
        case NODE_BOOL:   return [PyObject withBool:[(NSNumber *)[node fieldForKey:@"value"] boolValue]];
        case NODE_NONE:   return [PyObject none];
        case NODE_IDENTIFIER: {
            NSString *name = [node fieldForKey:@"name"];
            PyObject *v = [env get:name];
            if (!v) { fprintf(stderr, "NameError: name '%s' is not defined\n", name.UTF8String); exit(1); }
            return v;
        }
        case NODE_BINOP: {
            PyObject *l = [self evalExpr:[node fieldForKey:@"left"] inEnv:env];
            PyObject *r = [self evalExpr:[node fieldForKey:@"right"] inEnv:env];
            return [self applyBinOp:[node fieldForKey:@"op"] left:l right:r];
        }
        case NODE_UNARYOP: {
            NSString *op = [node fieldForKey:@"op"];
            PyObject *operand = [self evalExpr:[node fieldForKey:@"operand"] inEnv:env];
            if ([op isEqualToString:@"-"]) {
                if ([operand.type isEqualToString:@"int"]) return [PyObject withInt:-[(NSNumber *)operand.value longLongValue]];
                return [PyObject withFloat:-[(NSNumber *)operand.value doubleValue]];
            }
            if ([op isEqualToString:@"not"]) return [PyObject withBool:![operand isTruthy]];
            return operand;
        }
        case NODE_COMPARE: {
            PyObject *l = [self evalExpr:[node fieldForKey:@"left"] inEnv:env];
            PyObject *r = [self evalExpr:[node fieldForKey:@"right"] inEnv:env];
            return [self applyCompare:[node fieldForKey:@"op"] left:l right:r];
        }
        case NODE_BOOLOP: {
            NSString *op = [node fieldForKey:@"op"];
            PyObject *l = [self evalExpr:[node fieldForKey:@"left"] inEnv:env];
            if ([op isEqualToString:@"and"]) return [l isTruthy] ? [self evalExpr:[node fieldForKey:@"right"] inEnv:env] : l;
            return [l isTruthy] ? l : [self evalExpr:[node fieldForKey:@"right"] inEnv:env];
        }
        case NODE_CALL: {
            PyObject *func = [self evalExpr:[node fieldForKey:@"func"] inEnv:env];
            NSArray<ASTNode *> *argNodes = [node fieldForKey:@"args"];
            NSDictionary *kwargNodes = [node fieldForKey:@"kwargs"];
            NSMutableArray *args = [NSMutableArray array];
            for (ASTNode *a in argNodes) [args addObject:[self evalExpr:a inEnv:env]];
            NSMutableDictionary *kwargs = [NSMutableDictionary dictionary];
            for (NSString *k in kwargNodes) kwargs[k] = [self evalExpr:kwargNodes[k] inEnv:env];
            return [self callFunc:func args:args kwargs:kwargs];
        }
        case NODE_LIST: {
            NSArray<ASTNode *> *elts = [node fieldForKey:@"elts"];
            NSMutableArray *lst = [NSMutableArray array];
            for (ASTNode *e in elts) [lst addObject:[self evalExpr:e inEnv:env]];
            PyObject *r = [PyObject withList:lst];
            if ([node fieldForKey:@"isTuple"]) r.type = @"tuple";
            return r;
        }
        case NODE_DICT: {
            NSArray<ASTNode *> *keys = [node fieldForKey:@"keys"];
            NSArray<ASTNode *> *vals = [node fieldForKey:@"values"];
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (NSUInteger i=0;i<keys.count;i++) {
                PyObject *k = [self evalExpr:keys[i] inEnv:env];
                PyObject *v = [self evalExpr:vals[i] inEnv:env];
                d[[k repr]] = v;
            }
            return [PyObject withDict:d];
        }
        case NODE_SUBSCRIPT: {
            PyObject *obj = [self evalExpr:[node fieldForKey:@"value"] inEnv:env];
            PyObject *idx = [self evalExpr:[node fieldForKey:@"index"] inEnv:env];
            if ([obj.type isEqualToString:@"list"] || [obj.type isEqualToString:@"tuple"]) {
                long long i = [(NSNumber *)idx.value longLongValue];
                NSMutableArray *arr = (NSMutableArray *)obj.value;
                if (i<0) i+=arr.count;
                if (i<0||(NSUInteger)i>=arr.count) { fprintf(stderr,"IndexError: index out of range\n"); exit(1); }
                return arr[(NSUInteger)i];
            }
            if ([obj.type isEqualToString:@"str"]) {
                long long i = [(NSNumber *)idx.value longLongValue];
                NSString *s = (NSString *)obj.value;
                if (i<0) i+=s.length;
                return [PyObject withString:[NSString stringWithFormat:@"%C", [s characterAtIndex:(NSUInteger)i]]];
            }
            if ([obj.type isEqualToString:@"dict"]) {
                PyObject *v = ((NSMutableDictionary *)obj.value)[[idx repr]];
                if (!v) { fprintf(stderr,"KeyError\n"); exit(1); }
                return v;
            }
            return [PyObject none];
        }
        case NODE_ATTRIBUTE: {
            PyObject *obj = [self evalExpr:[node fieldForKey:@"value"] inEnv:env];
            NSString *attr = [node fieldForKey:@"attr"];
            return [self getAttribute:attr ofObject:obj];
        }
        default: return [PyObject none];
    }
}

- (PyObject *)getAttribute:(NSString *)attr ofObject:(PyObject *)obj {
    // Check attrs dict first
    if (obj.attrs && obj.attrs[attr]) return obj.attrs[attr];

    // Module attributes
    if ([obj.type isEqualToString:@"module"]) {
        return obj.attrs[attr] ?: [PyObject none];
    }

    // Instance methods
    if ([obj.type isEqualToString:@"instance"]) {
        NSDictionary *methods = ((NSDictionary *)obj.value)[@"classMethods"];
        PyObject *method = methods[attr];
        if (method) {
            // Bind self
            PyObject *bound = [[PyObject alloc] init]; bound.type = @"boundmethod";
            bound.value = @{@"func": method, @"self": obj};
            return bound;
        }
    }

    // Built-in string methods
    if ([obj.type isEqualToString:@"str"]) {
        NSString *s = (NSString *)obj.value;
        __block PyObject *result = nil;
        if ([attr isEqualToString:@"upper"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) { return [PyObject withString:[captured uppercaseString]]; };
        } else if ([attr isEqualToString:@"lower"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) { return [PyObject withString:[captured lowercaseString]]; };
        } else if ([attr isEqualToString:@"strip"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) { return [PyObject withString:[captured stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]; };
        } else if ([attr isEqualToString:@"split"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSString *sep = (a.count && ![[(PyObject*)a[0] type] isEqualToString:@"none"]) ? [(PyObject*)a[0] repr] : nil;
                NSArray *parts = sep ? [captured componentsSeparatedByString:sep] : [captured componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSMutableArray *lst = [NSMutableArray array];
                for (NSString *p in parts) if (p.length||sep) [lst addObject:[PyObject withString:p]];
                return [PyObject withList:lst];
            };
        } else if ([attr isEqualToString:@"join"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *sep = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *lst = a.firstObject;
                NSMutableArray *parts = [NSMutableArray array];
                for (PyObject *o in (NSArray *)lst.value) [parts addObject:[o repr]];
                return [PyObject withString:[parts componentsJoinedByString:sep]];
            };
        } else if ([attr isEqualToString:@"replace"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                if (a.count<2) return [PyObject withString:captured];
                return [PyObject withString:[captured stringByReplacingOccurrencesOfString:[(PyObject *)a[0] repr] withString:[(PyObject *)a[1] repr]]];
            };
        } else if ([attr isEqualToString:@"startswith"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                return [PyObject withBool:[captured hasPrefix:[(PyObject *)a[0] repr]]];
            };
        } else if ([attr isEqualToString:@"endswith"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                return [PyObject withBool:[captured hasSuffix:[(PyObject *)a[0] repr]]];
            };
        } else if ([attr isEqualToString:@"find"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSString *sub = [(PyObject *)a[0] repr];
                NSRange r = [captured rangeOfString:sub];
                return [PyObject withInt:r.location==NSNotFound ? -1 : (long long)r.location];
            };
        } else if ([attr isEqualToString:@"count"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSString *sub = [(PyObject *)a[0] repr]; long long cnt=0;
                NSRange r = NSMakeRange(0, captured.length);
                while (YES) {
                    NSRange f = [captured rangeOfString:sub options:0 range:r];
                    if (f.location==NSNotFound) break;
                    cnt++; r = NSMakeRange(f.location+f.length, captured.length-f.location-f.length);
                }
                return [PyObject withInt:cnt];
            };
        } else if ([attr isEqualToString:@"format"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSString *captured = s;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSMutableString *res = [NSMutableString stringWithString:captured];
                // Simple positional formatting
                NSUInteger idx2 = 0;
                while (YES) {
                    NSRange rb = [res rangeOfString:@"{}" options:0 range:NSMakeRange(0, res.length)];
                    if (rb.location==NSNotFound) break;
                    if (idx2 < a.count) [res replaceCharactersInRange:rb withString:[(PyObject *)a[idx2++] repr]];
                    else break;
                }
                return [PyObject withString:res];
            };
        }
        if (result) return result;
    }

    // List methods
    if ([obj.type isEqualToString:@"list"]) {
        NSMutableArray *lst = (NSMutableArray *)obj.value;
        PyObject *result = nil;
        if ([attr isEqualToString:@"append"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) { [captured addObject:a[0]]; return [PyObject none]; };
        } else if ([attr isEqualToString:@"pop"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                if (!captured.count) { fprintf(stderr,"IndexError: pop from empty list\n"); exit(1); }
                long long i = a.count ? [(NSNumber *)((PyObject *)a[0]).value longLongValue] : (long long)captured.count-1;
                if (i<0) i+=captured.count;
                PyObject *v = captured[(NSUInteger)i]; [captured removeObjectAtIndex:(NSUInteger)i]; return v;
            };
        } else if ([attr isEqualToString:@"extend"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *other = a[0];
                [captured addObjectsFromArray:(NSArray *)other.value];
                return [PyObject none];
            };
        } else if ([attr isEqualToString:@"insert"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                long long idx2 = [(NSNumber *)((PyObject *)a[0]).value longLongValue];
                if (idx2<0) idx2=0; if ((NSUInteger)idx2>captured.count) idx2=captured.count;
                [captured insertObject:a[1] atIndex:(NSUInteger)idx2];
                return [PyObject none];
            };
        } else if ([attr isEqualToString:@"remove"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            __weak typeof(self) ws = self;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *target = a[0];
                for (NSUInteger i2=0;i2<captured.count;i2++) {
                    if ([[ws applyCompare:@"==" left:captured[i2] right:target] isTruthy]) {
                        [captured removeObjectAtIndex:i2]; return [PyObject none];
                    }
                }
                fprintf(stderr,"ValueError: item not in list\n"); exit(1);
            };
        } else if ([attr isEqualToString:@"sort"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                BOOL rev = [(NSNumber *)((PyObject *)kw[@"reverse"]).value boolValue];
                [captured sortUsingComparator:^NSComparisonResult(PyObject *x, PyObject *y) {
                    double xv,yv;
                    if ([x.type isEqualToString:@"str"]&&[y.type isEqualToString:@"str"])
                        return [(NSString *)x.value compare:(NSString *)y.value];
                    xv=[(NSNumber *)x.value doubleValue]; yv=[(NSNumber *)y.value doubleValue];
                    NSComparisonResult r = xv<yv?NSOrderedAscending:xv>yv?NSOrderedDescending:NSOrderedSame;
                    return rev?-r:r;
                }];
                return [PyObject none];
            };
        } else if ([attr isEqualToString:@"index"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            __weak typeof(self) ws = self;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *target = a[0];
                for (NSUInteger i2=0;i2<captured.count;i2++) {
                    if ([[ws applyCompare:@"==" left:captured[i2] right:target] isTruthy])
                        return [PyObject withInt:i2];
                }
                fprintf(stderr,"ValueError: item not in list\n"); exit(1);
            };
        } else if ([attr isEqualToString:@"reverse"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSMutableArray *rev = [[captured reverseObjectEnumerator].allObjects mutableCopy];
                [captured setArray:rev]; return [PyObject none];
            };
        } else if ([attr isEqualToString:@"count"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableArray *captured = lst;
            __weak typeof(self) ws = self;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *target = a[0]; long long cnt=0;
                for (PyObject *o in captured) if ([[ws applyCompare:@"==" left:o right:target] isTruthy]) cnt++;
                return [PyObject withInt:cnt];
            };
        }
        if (result) return result;
    }

    // Dict methods
    if ([obj.type isEqualToString:@"dict"]) {
        NSMutableDictionary *d = (NSMutableDictionary *)obj.value;
        PyObject *result = nil;
        if ([attr isEqualToString:@"keys"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSMutableArray *lst = [NSMutableArray array];
                for (NSString *k in captured) [lst addObject:[PyObject withString:k]];
                return [PyObject withList:lst];
            };
        } else if ([attr isEqualToString:@"values"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSMutableArray *lst = [NSMutableArray array];
                for (NSString *k in captured) [lst addObject:captured[k]];
                return [PyObject withList:lst];
            };
        } else if ([attr isEqualToString:@"items"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSMutableArray *lst = [NSMutableArray array];
                for (NSString *k in captured) {
                    NSMutableArray *pair = [NSMutableArray arrayWithObjects:[PyObject withString:k], captured[k], nil];
                    [lst addObject:[PyObject withList:pair]];
                }
                return [PyObject withList:lst];
            };
        } else if ([attr isEqualToString:@"get"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                PyObject *key = a[0]; PyObject *def = a.count>1 ? a[1] : [PyObject none];
                PyObject *v = captured[[key repr]];
                return v ?: def;
            };
        } else if ([attr isEqualToString:@"update"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                if (a.count) [captured addEntriesFromDictionary:(NSDictionary *)((PyObject *)a[0]).value];
                return [PyObject none];
            };
        } else if ([attr isEqualToString:@"pop"]) {
            result = [[PyObject alloc] init]; result.type = @"builtin";
            NSMutableDictionary *captured = d;
            result.value = ^PyObject *(NSArray *a, NSDictionary *kw) {
                NSString *k = [(PyObject *)a[0] repr]; PyObject *v = captured[k];
                if (!v) { if(a.count>1) return a[1]; fprintf(stderr,"KeyError\n"); exit(1); }
                [captured removeObjectForKey:k]; return v;
            };
        }
        if (result) return result;
    }

    // Check attrs
    if (obj.attrs && obj.attrs[attr]) return obj.attrs[attr];
    fprintf(stderr, "AttributeError: '%s' object has no attribute '%s'\n", obj.type.UTF8String, attr.UTF8String);
    exit(1);
}

- (PyObject *)callFunc:(PyObject *)func args:(NSMutableArray *)args kwargs:(NSMutableDictionary *)kwargs {
    if ([func.type isEqualToString:@"builtin"]) {
        PyObject *(^blk)(NSArray *, NSDictionary *) = (PyObject *(^)(NSArray *, NSDictionary *))func.value;
        return blk(args, kwargs) ?: [PyObject none];
    }

    if ([func.type isEqualToString:@"boundmethod"]) {
        NSDictionary *bm = (NSDictionary *)func.value;
        PyObject *self2 = bm[@"self"];
        PyObject *method = bm[@"func"];
        NSMutableArray *newArgs = [NSMutableArray arrayWithObject:self2];
        [newArgs addObjectsFromArray:args];
        return [self callFunc:method args:newArgs kwargs:kwargs];
    }

    if ([func.type isEqualToString:@"class"]) {
        // Instantiate
        NSDictionary *clsDict = (NSDictionary *)func.value;
        PyObject *instance = [[PyObject alloc] init]; instance.type = @"instance";
        instance.attrs = [NSMutableDictionary dictionary];
        NSDictionary *methods = clsDict[@"methods"];
        NSMutableDictionary *instData = [NSMutableDictionary dictionaryWithDictionary:@{
            @"class": clsDict[@"name"], @"classMethods": methods
        }];
        instance.value = instData;
        // Call __init__ if exists
        PyObject *initFn = methods[@"__init__"];
        if (initFn) {
            NSMutableArray *initArgs = [NSMutableArray arrayWithObject:instance];
            [initArgs addObjectsFromArray:args];
            [self callFunc:initFn args:initArgs kwargs:kwargs];
        }
        return instance;
    }

    if ([func.type isEqualToString:@"func"]) {
        NSDictionary *fdict = (NSDictionary *)func.value;
        NSArray *params = fdict[@"params"];
        NSDictionary *defaults = fdict[@"defaults"];
        NSArray *body = fdict[@"body"];
        Environment *closure = fdict[@"closure"];
        Environment *callEnv = [[Environment alloc] initWithParent:closure];

        // Bind args
        for (NSUInteger i=0;i<params.count;i++) {
            NSString *pname = params[i];
            if (i < args.count) {
                [callEnv setLocal:pname value:args[i]];
            } else if (defaults[pname]) {
                [callEnv setLocal:pname value:[self evalExpr:defaults[pname] inEnv:closure]];
            } else if (kwargs[pname]) {
                [callEnv setLocal:pname value:kwargs[pname]];
            }
        }
        // Bind kwargs not already bound
        for (NSString *k in kwargs) {
            if (![callEnv has:k]) [callEnv setLocal:k value:kwargs[k]];
        }

        @try {
            [self execBlock:body inEnv:callEnv];
        } @catch (ReturnSignal *ret) {
            return ret.value;
        }
        return [PyObject none];
    }

    fprintf(stderr, "TypeError: '%s' object is not callable\n", func.type.UTF8String);
    exit(1);
}

- (PyObject *)applyBinOp:(NSString *)op left:(PyObject *)l right:(PyObject *)r {
    // String operations
    if ([l.type isEqualToString:@"str"] || [r.type isEqualToString:@"str"]) {
        if ([op isEqualToString:@"+"]) {
            return [PyObject withString:[[l repr] stringByAppendingString:[r repr]]];
        }
        if ([op isEqualToString:@"*"]) {
            NSString *s = [l.type isEqualToString:@"str"] ? (NSString *)l.value : (NSString *)r.value;
            long long n = [l.type isEqualToString:@"int"] ? [(NSNumber *)l.value longLongValue] : [(NSNumber *)r.value longLongValue];
            NSMutableString *res = [NSMutableString string];
            for (long long i=0;i<n;i++) [res appendString:s];
            return [PyObject withString:res];
        }
        if ([op isEqualToString:@"%"]) {
            // String formatting
            NSString *fmt = (NSString *)l.value;
            // Very basic %s, %d, %f support
            NSMutableString *res = [NSMutableString stringWithString:fmt];
            if ([r.type isEqualToString:@"list"] || [r.type isEqualToString:@"tuple"]) {
                NSArray *items = (NSArray *)r.value;
                NSUInteger idx2 = 0;
                NSMutableString *out = [NSMutableString string];
                NSUInteger i=0;
                while (i<fmt.length) {
                    unichar c = [fmt characterAtIndex:i];
                    if (c=='%' && i+1<fmt.length) {
                        unichar n = [fmt characterAtIndex:i+1];
                        if ((n=='s'||n=='d'||n=='f'||n=='g')&&idx2<items.count) {
                            [out appendString:[(PyObject *)items[idx2++] repr]]; i+=2; continue;
                        }
                    }
                    [out appendFormat:@"%C", c]; i++;
                }
                return [PyObject withString:out];
            } else {
                // Single item
                NSRange r2 = [res rangeOfString:@"%s"]; if (r2.location!=NSNotFound) [res replaceCharactersInRange:r2 withString:[r repr]];
                r2 = [res rangeOfString:@"%d"]; if (r2.location!=NSNotFound) [res replaceCharactersInRange:r2 withString:[r repr]];
                r2 = [res rangeOfString:@"%f"]; if (r2.location!=NSNotFound) [res replaceCharactersInRange:r2 withString:[r repr]];
                return [PyObject withString:res];
            }
        }
    }

    // List operations
    if ([l.type isEqualToString:@"list"] && [op isEqualToString:@"+"]) {
        NSMutableArray *res = [NSMutableArray arrayWithArray:(NSArray *)l.value];
        [res addObjectsFromArray:(NSArray *)r.value];
        return [PyObject withList:res];
    }
    if ([l.type isEqualToString:@"list"] && [op isEqualToString:@"*"]) {
        long long n = [(NSNumber *)r.value longLongValue];
        NSMutableArray *res = [NSMutableArray array];
        for (long long i=0;i<n;i++) [res addObjectsFromArray:(NSArray *)l.value];
        return [PyObject withList:res];
    }

    // Numeric
    BOOL isFloat = [l.type isEqualToString:@"float"] || [r.type isEqualToString:@"float"];
    double lv = [l.type isEqualToString:@"bool"] ? [(NSNumber *)l.value boolValue] : [(NSNumber *)l.value doubleValue];
    double rv = [r.type isEqualToString:@"bool"] ? [(NSNumber *)r.value boolValue] : [(NSNumber *)r.value doubleValue];

    if ([op isEqualToString:@"+"]) return isFloat ? [PyObject withFloat:lv+rv] : [PyObject withInt:(long long)(lv+rv)];
    if ([op isEqualToString:@"-"]) return isFloat ? [PyObject withFloat:lv-rv] : [PyObject withInt:(long long)(lv-rv)];
    if ([op isEqualToString:@"*"]) return isFloat ? [PyObject withFloat:lv*rv] : [PyObject withInt:(long long)(lv*rv)];
    if ([op isEqualToString:@"/"]) return [PyObject withFloat:lv/rv];
    if ([op isEqualToString:@"//"]) return [PyObject withInt:(long long)floor(lv/rv)];
    if ([op isEqualToString:@"%"]) {
        if (isFloat) return [PyObject withFloat:fmod(lv,rv)];
        return [PyObject withInt:((long long)lv % (long long)rv)];
    }
    if ([op isEqualToString:@"**"]) return [PyObject withFloat:pow(lv,rv)];
    return [PyObject none];
}

- (PyObject *)applyCompare:(NSString *)op left:(PyObject *)l right:(PyObject *)r {
    // Equality by repr for simple cases
    if ([op isEqualToString:@"=="]) {
        if ([l.type isEqualToString:@"none"] && [r.type isEqualToString:@"none"]) return [PyObject withBool:YES];
        if ([l.type isEqualToString:@"str"] && [r.type isEqualToString:@"str"])
            return [PyObject withBool:[(NSString *)l.value isEqualToString:(NSString *)r.value]];
        if ([l.type isEqualToString:@"bool"] || [r.type isEqualToString:@"bool"]) {
            BOOL lb = [l isTruthy], rb = [r isTruthy];
            if ([l.type isEqualToString:@"bool"] && [r.type isEqualToString:@"bool"]) return [PyObject withBool:lb==rb];
        }
        double lv=[(NSNumber *)l.value doubleValue], rv=[(NSNumber *)r.value doubleValue];
        return [PyObject withBool:lv==rv];
    }
    if ([op isEqualToString:@"!="]) {
        return [PyObject withBool:![[self applyCompare:@"==" left:l right:r] isTruthy]];
    }
    if ([op isEqualToString:@"in"]) {
        if ([r.type isEqualToString:@"list"] || [r.type isEqualToString:@"tuple"]) {
            for (PyObject *o in (NSArray *)r.value)
                if ([[self applyCompare:@"==" left:l right:o] isTruthy]) return [PyObject withBool:YES];
        } else if ([r.type isEqualToString:@"str"]) {
            return [PyObject withBool:[(NSString *)r.value containsString:[l repr]]];
        } else if ([r.type isEqualToString:@"dict"]) {
            return [PyObject withBool:((NSDictionary *)r.value)[[l repr]] != nil];
        }
        return [PyObject withBool:NO];
    }
    if ([op isEqualToString:@"not in"]) {
        return [PyObject withBool:![[self applyCompare:@"in" left:l right:r] isTruthy]];
    }
    // Numeric comparisons
    double lv, rv;
    if ([l.type isEqualToString:@"str"] && [r.type isEqualToString:@"str"]) {
        NSComparisonResult cr = [(NSString *)l.value compare:(NSString *)r.value];
        if ([op isEqualToString:@"<"]) return [PyObject withBool:cr==NSOrderedAscending];
        if ([op isEqualToString:@">"]) return [PyObject withBool:cr==NSOrderedDescending];
        if ([op isEqualToString:@"<="]) return [PyObject withBool:cr!=NSOrderedDescending];
        if ([op isEqualToString:@">="]) return [PyObject withBool:cr!=NSOrderedAscending];
    }
    lv=[(NSNumber *)l.value doubleValue]; rv=[(NSNumber *)r.value doubleValue];
    if ([op isEqualToString:@"<"])  return [PyObject withBool:lv<rv];
    if ([op isEqualToString:@">"])  return [PyObject withBool:lv>rv];
    if ([op isEqualToString:@"<="]) return [PyObject withBool:lv<=rv];
    if ([op isEqualToString:@">="]) return [PyObject withBool:lv>=rv];
    return [PyObject withBool:NO];
}

@end
