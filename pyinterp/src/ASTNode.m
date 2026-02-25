#import "../include/ASTNode.h"

@implementation ASTNode
- (instancetype)initWithType:(NodeType)type {
    self = [super init];
    _type = type;
    _fields = [NSMutableDictionary dictionary];
    return self;
}
- (void)setField:(id)value forKey:(NSString *)key { _fields[key] = value; }
- (id)fieldForKey:(NSString *)key { return _fields[key]; }
- (NSString *)description { return [NSString stringWithFormat:@"ASTNode(%ld)", (long)_type]; }
@end
