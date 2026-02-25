#import <Foundation/Foundation.h>
#import "Lexer.h"
#import "ASTNode.h"

@interface Parser : NSObject
- (instancetype)initWithTokens:(NSArray<Token *> *)tokens;
- (NSArray<ASTNode *> *)parse;
@end
