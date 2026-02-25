#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NodeType) {
    NODE_NUMBER,
    NODE_STRING,
    NODE_BOOL,
    NODE_NONE,
    NODE_IDENTIFIER,
    NODE_BINOP,
    NODE_UNARYOP,
    NODE_ASSIGN,
    NODE_AUGASSIGN,
    NODE_IF,
    NODE_WHILE,
    NODE_FOR,
    NODE_FUNCDEF,
    NODE_CALL,
    NODE_RETURN,
    NODE_BLOCK,
    NODE_PRINT,
    NODE_COMPARE,
    NODE_BOOLOP,
    NODE_LIST,
    NODE_DICT,
    NODE_SUBSCRIPT,
    NODE_ATTRIBUTE,
    NODE_BREAK,
    NODE_CONTINUE,
    NODE_PASS,
    NODE_CLASS,
    NODE_IMPORT,
    NODE_LAMBDA,
};

@interface ASTNode : NSObject
@property (nonatomic) NodeType type;
@property (nonatomic, strong) NSMutableDictionary *fields;
@property (nonatomic) NSInteger line;
- (instancetype)initWithType:(NodeType)type;
- (void)setField:(id)value forKey:(NSString *)key;
- (id)fieldForKey:(NSString *)key;
@end
