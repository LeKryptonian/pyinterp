#import "../include/Lexer.h"

@implementation Token
- (instancetype)initWithType:(TokenType)type value:(NSString *)value line:(NSInteger)line {
    self = [super init];
    _type = type; _value = value; _line = line;
    return self;
}
- (NSString *)description { return [NSString stringWithFormat:@"Token(%ld, %@)", (long)_type, _value]; }
@end

@interface Lexer ()
@property NSString *source;
@property NSInteger pos;
@property NSInteger line;
@property NSMutableArray<NSNumber *> *indentStack;
@end

@implementation Lexer

- (instancetype)initWithSource:(NSString *)source {
    self = [super init];
    _source = source; _pos = 0; _line = 1;
    _indentStack = [NSMutableArray arrayWithObject:@0];
    return self;
}

- (unichar)current { return _pos < (NSInteger)_source.length ? [_source characterAtIndex:_pos] : 0; }
- (unichar)peek:(NSInteger)offset { NSInteger i = _pos+offset; return i < (NSInteger)_source.length ? [_source characterAtIndex:i] : 0; }
- (void)advance { _pos++; }

- (NSDictionary *)keywords {
    return @{
        @"def": @(TOKEN_DEF), @"return": @(TOKEN_RETURN), @"if": @(TOKEN_IF),
        @"elif": @(TOKEN_ELIF), @"else": @(TOKEN_ELSE), @"while": @(TOKEN_WHILE),
        @"for": @(TOKEN_FOR), @"in": @(TOKEN_IN), @"and": @(TOKEN_AND),
        @"or": @(TOKEN_OR), @"not": @(TOKEN_NOT), @"True": @(TOKEN_BOOL_TRUE),
        @"False": @(TOKEN_BOOL_FALSE), @"None": @(TOKEN_NONE), @"break": @(TOKEN_BREAK),
        @"continue": @(TOKEN_CONTINUE), @"pass": @(TOKEN_PASS), @"print": @(TOKEN_PRINT),
        @"import": @(TOKEN_IMPORT), @"class": @(TOKEN_CLASS),
    };
}

- (NSArray<Token *> *)tokenize {
    NSMutableArray<Token *> *tokens = [NSMutableArray array];
    BOOL atLineStart = YES;

    while (_pos <= (NSInteger)_source.length) {
        if (_pos == (NSInteger)_source.length) {
            // Emit dedents at EOF
            while (_indentStack.count > 1) {
                [_indentStack removeLastObject];
                [tokens addObject:[[Token alloc] initWithType:TOKEN_DEDENT value:@"" line:_line]];
            }
            [tokens addObject:[[Token alloc] initWithType:TOKEN_EOF value:@"" line:_line]];
            break;
        }

        unichar c = [self current];

        // Handle indentation at line start
        if (atLineStart) {
            NSInteger indent = 0;
            while (_pos < (NSInteger)_source.length && ([self current] == ' ' || [self current] == '\t')) {
                indent += ([self current] == '\t') ? 8 : 1;
                [self advance];
            }
            // Skip blank lines and comment lines
            if (_pos < (NSInteger)_source.length && ([self current] == '\n' || [self current] == '#')) {
                if ([self current] == '#') {
                    while (_pos < (NSInteger)_source.length && [self current] != '\n') [self advance];
                }
                if (_pos < (NSInteger)_source.length && [self current] == '\n') { [self advance]; _line++; }
                continue;
            }
            NSInteger curIndent = [_indentStack.lastObject integerValue];
            if (indent > curIndent) {
                [_indentStack addObject:@(indent)];
                [tokens addObject:[[Token alloc] initWithType:TOKEN_INDENT value:@"" line:_line]];
            } else {
                while (indent < [_indentStack.lastObject integerValue]) {
                    [_indentStack removeLastObject];
                    [tokens addObject:[[Token alloc] initWithType:TOKEN_DEDENT value:@"" line:_line]];
                }
            }
            atLineStart = NO;
            continue;
        }

        c = [self current];

        // Newline
        if (c == '\n') {
            [self advance]; _line++;
            // Only emit newline if last token is not indent/dedent/newline
            if (tokens.count > 0) {
                TokenType last = tokens.lastObject.type;
                if (last != TOKEN_NEWLINE && last != TOKEN_INDENT && last != TOKEN_DEDENT && last != TOKEN_COLON) {
                    [tokens addObject:[[Token alloc] initWithType:TOKEN_NEWLINE value:@"\n" line:_line-1]];
                }
            }
            atLineStart = YES;
            continue;
        }

        // Skip spaces/tabs (not at line start)
        if (c == ' ' || c == '\t' || c == '\r') { [self advance]; continue; }

        // Comments
        if (c == '#') {
            while (_pos < (NSInteger)_source.length && [self current] != '\n') [self advance];
            continue;
        }

        // Line continuation
        if (c == '\\' && [self peek:1] == '\n') { [self advance]; [self advance]; _line++; continue; }

        // String literals
        if (c == '"' || c == '\'') {
            [tokens addObject:[self readString:c]];
            continue;
        }

        // Numbers
        if (isdigit(c) || (c == '.' && isdigit([self peek:1]))) {
            [tokens addObject:[self readNumber]];
            continue;
        }

        // Identifiers / keywords
        if (isalpha(c) || c == '_') {
            NSMutableString *ident = [NSMutableString string];
            while (_pos < (NSInteger)_source.length && (isalnum([self current]) || [self current] == '_')) {
                [ident appendFormat:@"%c", [self current]];
                [self advance];
            }
            NSNumber *kwType = [self keywords][ident];
            TokenType tt = kwType ? (TokenType)kwType.integerValue : TOKEN_IDENTIFIER;
            [tokens addObject:[[Token alloc] initWithType:tt value:ident line:_line]];
            continue;
        }

        // Operators and delimiters
        Token *opTok = [self readOperator];
        if (opTok) { [tokens addObject:opTok]; continue; }

        // Unknown
        [self advance];
    }
    return tokens;
}

- (Token *)readString:(unichar)quote {
    NSMutableString *s = [NSMutableString string];
    [self advance]; // opening quote
    // Triple quote check
    BOOL triple = NO;
    if ([self current] == quote && [self peek:1] == quote) {
        [self advance]; [self advance]; triple = YES;
    }
    while (_pos < (NSInteger)_source.length) {
        unichar c = [self current];
        if (triple) {
            if (c == quote && [self peek:1] == quote && [self peek:2] == quote) {
                [self advance]; [self advance]; [self advance]; break;
            }
        } else {
            if (c == quote) { [self advance]; break; }
            if (c == '\n') break;
        }
        if (c == '\\') {
            [self advance];
            unichar esc = [self current]; [self advance];
            switch(esc) {
                case 'n': [s appendString:@"\n"]; break;
                case 't': [s appendString:@"\t"]; break;
                case '\\': [s appendString:@"\\"]; break;
                case '\'': [s appendString:@"'"]; break;
                case '"': [s appendString:@"\""]; break;
                default: [s appendFormat:@"\\%c", esc];
            }
        } else {
            [s appendFormat:@"%c", c];
            [self advance];
        }
    }
    return [[Token alloc] initWithType:TOKEN_STRING value:s line:_line];
}

- (Token *)readNumber {
    NSMutableString *s = [NSMutableString string];
    BOOL isFloat = NO;
    while (_pos < (NSInteger)_source.length && isdigit([self current])) {
        [s appendFormat:@"%c", [self current]]; [self advance];
    }
    if (_pos < (NSInteger)_source.length && [self current] == '.' && isdigit([self peek:1])) {
        isFloat = YES;
        [s appendString:@"."]; [self advance];
        while (_pos < (NSInteger)_source.length && isdigit([self current])) {
            [s appendFormat:@"%c", [self current]]; [self advance];
        }
    }
    if (_pos < (NSInteger)_source.length && ([self current] == 'e' || [self current] == 'E')) {
        isFloat = YES;
        [s appendFormat:@"%c", [self current]]; [self advance];
        if (_pos < (NSInteger)_source.length && ([self current] == '+' || [self current] == '-')) {
            [s appendFormat:@"%c", [self current]]; [self advance];
        }
        while (_pos < (NSInteger)_source.length && isdigit([self current])) {
            [s appendFormat:@"%c", [self current]]; [self advance];
        }
    }
    (void)isFloat;
    return [[Token alloc] initWithType:TOKEN_NUMBER value:s line:_line];
}

- (Token *)readOperator {
    unichar c = [self current];
    unichar n = [self peek:1];
    NSInteger ln = _line;

#define TOK2(a,b,t) if(c==a && n==b){[self advance];[self advance];return [[Token alloc]initWithType:t value:[NSString stringWithFormat:@"%c%c",a,b] line:ln];}
#define TOK1(a,t) if(c==a){[self advance];return [[Token alloc]initWithType:t value:[NSString stringWithFormat:@"%c",a] line:ln];}

    TOK2('+','=',TOKEN_PLUS_ASSIGN)
    TOK2('-','=',TOKEN_MINUS_ASSIGN)
    TOK2('*','=',TOKEN_STAR_ASSIGN)
    TOK2('/','=',TOKEN_SLASH_ASSIGN)
    TOK2('*','*',TOKEN_DOUBLESTAR)
    TOK2('/','/',TOKEN_DOUBLESLASH)
    TOK2('=','=',TOKEN_EQ)
    TOK2('!','=',TOKEN_NEQ)
    TOK2('<','=',TOKEN_LTE)
    TOK2('>','=',TOKEN_GTE)
    TOK1('+',TOKEN_PLUS)
    TOK1('-',TOKEN_MINUS)
    TOK1('*',TOKEN_STAR)
    TOK1('/',TOKEN_SLASH)
    TOK1('%',TOKEN_PERCENT)
    TOK1('<',TOKEN_LT)
    TOK1('>',TOKEN_GT)
    TOK1('=',TOKEN_ASSIGN)
    TOK1('(',TOKEN_LPAREN)
    TOK1(')',TOKEN_RPAREN)
    TOK1('[',TOKEN_LBRACKET)
    TOK1(']',TOKEN_RBRACKET)
    TOK1('{',TOKEN_LBRACE)
    TOK1('}',TOKEN_RBRACE)
    TOK1(':',TOKEN_COLON)
    TOK1(',',TOKEN_COMMA)
    TOK1('.',TOKEN_DOT)
    TOK1(';',TOKEN_SEMICOLON)
    return nil;
}

@end
