#import <Foundation/Foundation.h>
#import "ASTNode.h"

@interface PyObject : NSObject
@property (nonatomic, strong) NSString *type; // "int","float","str","bool","none","list","dict","func","class","instance"
@property (nonatomic, strong) id value;       // NSNumber, NSString, NSMutableArray, NSMutableDictionary
@property (nonatomic, strong) NSMutableDictionary *attrs;
+ (instancetype)withInt:(long long)v;
+ (instancetype)withFloat:(double)v;
+ (instancetype)withString:(NSString *)v;
+ (instancetype)withBool:(BOOL)v;
+ (instancetype)none;
+ (instancetype)withList:(NSMutableArray *)v;
+ (instancetype)withDict:(NSMutableDictionary *)v;
- (NSString *)repr;
- (BOOL)isTruthy;
@end

@interface Environment : NSObject
@property (nonatomic, weak) Environment *parent;
- (instancetype)initWithParent:(Environment *)parent;
- (PyObject *)get:(NSString *)name;
- (void)set:(NSString *)name value:(PyObject *)value;
- (void)setLocal:(NSString *)name value:(PyObject *)value;
- (BOOL)has:(NSString *)name;
@end

@interface Interpreter : NSObject
- (instancetype)init;
- (void)runStatements:(NSArray<ASTNode *> *)stmts;
@end
