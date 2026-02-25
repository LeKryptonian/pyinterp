#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TokenType) {
    // Literals
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_BOOL_TRUE,
    TOKEN_BOOL_FALSE,
    TOKEN_NONE,
    // Identifiers / Keywords
    TOKEN_IDENTIFIER,
    TOKEN_DEF,
    TOKEN_RETURN,
    TOKEN_IF,
    TOKEN_ELIF,
    TOKEN_ELSE,
    TOKEN_WHILE,
    TOKEN_FOR,
    TOKEN_IN,
    TOKEN_AND,
    TOKEN_OR,
    TOKEN_NOT,
    TOKEN_BREAK,
    TOKEN_CONTINUE,
    TOKEN_PASS,
    TOKEN_IMPORT,
    TOKEN_CLASS,
    TOKEN_PRINT,
    // Operators
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_DOUBLESLASH,
    TOKEN_PERCENT,
    TOKEN_DOUBLESTAR,
    TOKEN_EQ,
    TOKEN_NEQ,
    TOKEN_LT,
    TOKEN_GT,
    TOKEN_LTE,
    TOKEN_GTE,
    TOKEN_ASSIGN,
    TOKEN_PLUS_ASSIGN,
    TOKEN_MINUS_ASSIGN,
    TOKEN_STAR_ASSIGN,
    TOKEN_SLASH_ASSIGN,
    // Delimiters
    TOKEN_LPAREN,
    TOKEN_RPAREN,
    TOKEN_LBRACKET,
    TOKEN_RBRACKET,
    TOKEN_LBRACE,
    TOKEN_RBRACE,
    TOKEN_COLON,
    TOKEN_COMMA,
    TOKEN_DOT,
    TOKEN_SEMICOLON,
    // Special
    TOKEN_NEWLINE,
    TOKEN_INDENT,
    TOKEN_DEDENT,
    TOKEN_EOF,
};

@interface Token : NSObject
@property (nonatomic) TokenType type;
@property (nonatomic, strong) NSString *value;
@property (nonatomic) NSInteger line;
- (instancetype)initWithType:(TokenType)type value:(NSString *)value line:(NSInteger)line;
@end

@interface Lexer : NSObject
- (instancetype)initWithSource:(NSString *)source;
- (NSArray<Token *> *)tokenize;
@end
