#import "../include/Parser.h"

@interface Parser ()
@property NSArray<Token *> *tokens;
@property NSInteger pos;
@end

@implementation Parser

- (instancetype)initWithTokens:(NSArray<Token *> *)tokens {
    self = [super init];
    _tokens = tokens; _pos = 0;
    return self;
}

- (Token *)current { return _pos < (NSInteger)_tokens.count ? _tokens[_pos] : _tokens.lastObject; }
- (Token *)peek:(NSInteger)offset {
    NSInteger i = _pos + offset;
    return i < (NSInteger)_tokens.count ? _tokens[i] : _tokens.lastObject;
}
- (Token *)advance { Token *t = [self current]; _pos++; return t; }
- (BOOL)check:(TokenType)type { return [self current].type == type; }
- (Token *)expect:(TokenType)type {
    if (![self check:type]) {
        fprintf(stderr, "Syntax error: expected token %ld but got '%s' (type %ld) at line %ld\n",
            (long)type, [self current].value.UTF8String, (long)[self current].type, (long)[self current].line);
        exit(1);
    }
    return [self advance];
}
- (BOOL)match:(TokenType)type { if ([self check:type]) { [self advance]; return YES; } return NO; }

- (void)skipNewlines {
    while ([self check:TOKEN_NEWLINE]) [self advance];
}

- (NSArray<ASTNode *> *)parse {
    NSMutableArray *stmts = [NSMutableArray array];
    [self skipNewlines];
    while (![self check:TOKEN_EOF]) {
        ASTNode *s = [self parseStatement];
        if (s) [stmts addObject:s];
        [self skipNewlines];
    }
    return stmts;
}

- (NSArray<ASTNode *> *)parseBlock {
    [self expect:TOKEN_INDENT];
    NSMutableArray *stmts = [NSMutableArray array];
    [self skipNewlines];
    while (![self check:TOKEN_DEDENT] && ![self check:TOKEN_EOF]) {
        ASTNode *s = [self parseStatement];
        if (s) [stmts addObject:s];
        [self skipNewlines];
    }
    [self match:TOKEN_DEDENT];
    return stmts;
}

- (ASTNode *)parseStatement {
    Token *cur = [self current];

    if (cur.type == TOKEN_NEWLINE) { [self advance]; return nil; }
    if (cur.type == TOKEN_PASS) { [self advance]; [self match:TOKEN_NEWLINE]; ASTNode *n = [[ASTNode alloc] initWithType:NODE_PASS]; return n; }
    if (cur.type == TOKEN_BREAK) { [self advance]; [self match:TOKEN_NEWLINE]; ASTNode *n = [[ASTNode alloc] initWithType:NODE_BREAK]; return n; }
    if (cur.type == TOKEN_CONTINUE) { [self advance]; [self match:TOKEN_NEWLINE]; ASTNode *n = [[ASTNode alloc] initWithType:NODE_CONTINUE]; return n; }
    if (cur.type == TOKEN_RETURN) return [self parseReturn];
    if (cur.type == TOKEN_IF) return [self parseIf];
    if (cur.type == TOKEN_WHILE) return [self parseWhile];
    if (cur.type == TOKEN_FOR) return [self parseFor];
    if (cur.type == TOKEN_DEF) return [self parseFuncDef];
    if (cur.type == TOKEN_CLASS) return [self parseClass];
    if (cur.type == TOKEN_PRINT) return [self parsePrint];
    if (cur.type == TOKEN_IMPORT) return [self parseImport];

    return [self parseExprStatement];
}

- (ASTNode *)parseReturn {
    [self advance]; // 'return'
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_RETURN];
    if (![self check:TOKEN_NEWLINE] && ![self check:TOKEN_EOF] && ![self check:TOKEN_DEDENT]) {
        [n setField:[self parseExpr] forKey:@"value"];
    }
    [self match:TOKEN_NEWLINE];
    return n;
}

- (ASTNode *)parseIf {
    [self advance]; // 'if'
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_IF];
    [n setField:[self parseExpr] forKey:@"test"];
    [self expect:TOKEN_COLON];
    [self match:TOKEN_NEWLINE];
    [n setField:[self parseBlock] forKey:@"body"];

    NSMutableArray *elifs = [NSMutableArray array];
    ASTNode *elseNode = nil;

    while ([self check:TOKEN_ELIF]) {
        [self advance];
        ASTNode *elif = [[ASTNode alloc] initWithType:NODE_IF];
        [elif setField:[self parseExpr] forKey:@"test"];
        [self expect:TOKEN_COLON];
        [self match:TOKEN_NEWLINE];
        [elif setField:[self parseBlock] forKey:@"body"];
        [elifs addObject:elif];
    }
    if ([self check:TOKEN_ELSE]) {
        [self advance];
        [self expect:TOKEN_COLON];
        [self match:TOKEN_NEWLINE];
        elseNode = [[ASTNode alloc] initWithType:NODE_BLOCK];
        [elseNode setField:[self parseBlock] forKey:@"stmts"];
    }
    [n setField:elifs forKey:@"elifs"];
    if (elseNode) [n setField:elseNode forKey:@"else"];
    return n;
}

- (ASTNode *)parseWhile {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_WHILE];
    [n setField:[self parseExpr] forKey:@"test"];
    [self expect:TOKEN_COLON];
    [self match:TOKEN_NEWLINE];
    [n setField:[self parseBlock] forKey:@"body"];
    return n;
}

- (ASTNode *)parseFor {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_FOR];
    // Target (possibly tuple)
    NSMutableArray *targets = [NSMutableArray array];
    [targets addObject:[self current].value];
    [self expect:TOKEN_IDENTIFIER];
    while ([self match:TOKEN_COMMA]) {
        [targets addObject:[self current].value];
        [self expect:TOKEN_IDENTIFIER];
    }
    [n setField:targets forKey:@"targets"];
    [self expect:TOKEN_IN];
    [n setField:[self parseExpr] forKey:@"iter"];
    [self expect:TOKEN_COLON];
    [self match:TOKEN_NEWLINE];
    [n setField:[self parseBlock] forKey:@"body"];
    return n;
}

- (ASTNode *)parseFuncDef {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_FUNCDEF];
    [n setField:[self current].value forKey:@"name"];
    [self expect:TOKEN_IDENTIFIER];
    [self expect:TOKEN_LPAREN];
    NSMutableArray *params = [NSMutableArray array];
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    while (![self check:TOKEN_RPAREN]) {
        NSString *pname = [self current].value;
        [self expect:TOKEN_IDENTIFIER];
        [params addObject:pname];
        if ([self match:TOKEN_ASSIGN]) {
            ASTNode *defVal = [self parseExpr];
            defaults[pname] = defVal;
        }
        if (![self check:TOKEN_RPAREN]) [self expect:TOKEN_COMMA];
    }
    [self expect:TOKEN_RPAREN];
    [n setField:params forKey:@"params"];
    [n setField:defaults forKey:@"defaults"];
    [self expect:TOKEN_COLON];
    [self match:TOKEN_NEWLINE];
    [n setField:[self parseBlock] forKey:@"body"];
    return n;
}

- (ASTNode *)parseClass {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_CLASS];
    [n setField:[self current].value forKey:@"name"];
    [self expect:TOKEN_IDENTIFIER];
    NSMutableArray *bases = [NSMutableArray array];
    if ([self match:TOKEN_LPAREN]) {
        while (![self check:TOKEN_RPAREN]) {
            [bases addObject:[self current].value];
            [self expect:TOKEN_IDENTIFIER];
            if (![self check:TOKEN_RPAREN]) [self match:TOKEN_COMMA];
        }
        [self expect:TOKEN_RPAREN];
    }
    [n setField:bases forKey:@"bases"];
    [self expect:TOKEN_COLON];
    [self match:TOKEN_NEWLINE];
    [n setField:[self parseBlock] forKey:@"body"];
    return n;
}

- (ASTNode *)parsePrint {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_PRINT];
    NSMutableArray *args = [NSMutableArray array];
    if ([self match:TOKEN_LPAREN]) {
        while (![self check:TOKEN_RPAREN] && ![self check:TOKEN_EOF]) {
            [args addObject:[self parseExpr]];
            if (![self check:TOKEN_RPAREN]) [self match:TOKEN_COMMA];
        }
        [self expect:TOKEN_RPAREN];
    } else {
        // Python 2 style print
        while (![self check:TOKEN_NEWLINE] && ![self check:TOKEN_EOF]) {
            [args addObject:[self parseExpr]];
            if (![self check:TOKEN_NEWLINE]) [self match:TOKEN_COMMA];
        }
    }
    [n setField:args forKey:@"args"];
    [self match:TOKEN_NEWLINE];
    return n;
}

- (ASTNode *)parseImport {
    [self advance];
    ASTNode *n = [[ASTNode alloc] initWithType:NODE_IMPORT];
    [n setField:[self current].value forKey:@"module"];
    [self expect:TOKEN_IDENTIFIER];
    [self match:TOKEN_NEWLINE];
    return n;
}

- (ASTNode *)parseExprStatement {
    ASTNode *expr = [self parseExpr];
    // Check for assignment
    if ([self check:TOKEN_ASSIGN]) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_ASSIGN];
        [n setField:expr forKey:@"target"];
        [n setField:[self parseExpr] forKey:@"value"];
        [self match:TOKEN_NEWLINE];
        return n;
    }
    // Augmented assignment
    TokenType aug = [self current].type;
    if (aug == TOKEN_PLUS_ASSIGN || aug == TOKEN_MINUS_ASSIGN ||
        aug == TOKEN_STAR_ASSIGN || aug == TOKEN_SLASH_ASSIGN) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_AUGASSIGN];
        [n setField:expr forKey:@"target"];
        NSString *op = aug == TOKEN_PLUS_ASSIGN ? @"+" : aug == TOKEN_MINUS_ASSIGN ? @"-" :
                       aug == TOKEN_STAR_ASSIGN ? @"*" : @"/";
        [n setField:op forKey:@"op"];
        [n setField:[self parseExpr] forKey:@"value"];
        [self match:TOKEN_NEWLINE];
        return n;
    }
    [self match:TOKEN_NEWLINE];
    return expr;
}

// Expression parsing with precedence
- (ASTNode *)parseExpr { return [self parseBoolOr]; }

- (ASTNode *)parseBoolOr {
    ASTNode *left = [self parseBoolAnd];
    while ([self check:TOKEN_OR]) {
        [self advance];
        ASTNode *right = [self parseBoolAnd];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_BOOLOP];
        [n setField:@"or" forKey:@"op"];
        [n setField:left forKey:@"left"];
        [n setField:right forKey:@"right"];
        left = n;
    }
    return left;
}

- (ASTNode *)parseBoolAnd {
    ASTNode *left = [self parseBoolNot];
    while ([self check:TOKEN_AND]) {
        [self advance];
        ASTNode *right = [self parseBoolNot];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_BOOLOP];
        [n setField:@"and" forKey:@"op"];
        [n setField:left forKey:@"left"];
        [n setField:right forKey:@"right"];
        left = n;
    }
    return left;
}

- (ASTNode *)parseBoolNot {
    if ([self check:TOKEN_NOT]) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_UNARYOP];
        [n setField:@"not" forKey:@"op"];
        [n setField:[self parseBoolNot] forKey:@"operand"];
        return n;
    }
    return [self parseComparison];
}

- (ASTNode *)parseComparison {
    ASTNode *left = [self parseAddSub];
    NSArray *cmpOps = @[@(TOKEN_EQ),@(TOKEN_NEQ),@(TOKEN_LT),@(TOKEN_GT),@(TOKEN_LTE),@(TOKEN_GTE),@(TOKEN_IN),@(TOKEN_NOT)];
    while (YES) {
        BOOL found = NO;
        for (NSNumber *op in cmpOps) {
            if ([self check:(TokenType)op.integerValue]) { found = YES; break; }
        }
        if (!found) break;
        NSString *opStr;
        if ([self check:TOKEN_NOT]) { [self advance]; [self expect:TOKEN_IN]; opStr = @"not in"; }
        else if ([self check:TOKEN_IN]) { [self advance]; opStr = @"in"; }
        else {
            Token *t = [self advance];
            opStr = t.value;
        }
        ASTNode *right = [self parseAddSub];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_COMPARE];
        [n setField:opStr forKey:@"op"];
        [n setField:left forKey:@"left"];
        [n setField:right forKey:@"right"];
        left = n;
    }
    return left;
}

- (ASTNode *)parseAddSub {
    ASTNode *left = [self parseMulDiv];
    while ([self check:TOKEN_PLUS] || [self check:TOKEN_MINUS]) {
        NSString *op = [self advance].value;
        ASTNode *right = [self parseMulDiv];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_BINOP];
        [n setField:op forKey:@"op"];
        [n setField:left forKey:@"left"];
        [n setField:right forKey:@"right"];
        left = n;
    }
    return left;
}

- (ASTNode *)parseMulDiv {
    ASTNode *left = [self parseUnary];
    while ([self check:TOKEN_STAR] || [self check:TOKEN_SLASH] ||
           [self check:TOKEN_PERCENT] || [self check:TOKEN_DOUBLESLASH]) {
        NSString *op = [self advance].value;
        ASTNode *right = [self parseUnary];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_BINOP];
        [n setField:op forKey:@"op"];
        [n setField:left forKey:@"left"];
        [n setField:right forKey:@"right"];
        left = n;
    }
    return left;
}

- (ASTNode *)parseUnary {
    if ([self check:TOKEN_MINUS]) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_UNARYOP];
        [n setField:@"-" forKey:@"op"];
        [n setField:[self parsePower] forKey:@"operand"];
        return n;
    }
    if ([self check:TOKEN_PLUS]) { [self advance]; return [self parsePower]; }
    return [self parsePower];
}

- (ASTNode *)parsePower {
    ASTNode *base = [self parsePostfix];
    if ([self check:TOKEN_DOUBLESTAR]) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_BINOP];
        [n setField:@"**" forKey:@"op"];
        [n setField:base forKey:@"left"];
        [n setField:[self parseUnary] forKey:@"right"];
        return n;
    }
    return base;
}

- (ASTNode *)parsePostfix {
    ASTNode *node = [self parsePrimary];
    while (YES) {
        if ([self check:TOKEN_LPAREN]) {
            [self advance];
            NSMutableArray *args = [NSMutableArray array];
            NSMutableDictionary *kwargs = [NSMutableDictionary dictionary];
            while (![self check:TOKEN_RPAREN] && ![self check:TOKEN_EOF]) {
                // Check for keyword arg
                if ([self check:TOKEN_IDENTIFIER] && [self peek:1].type == TOKEN_ASSIGN) {
                    NSString *kname = [self advance].value;
                    [self advance]; // '='
                    kwargs[kname] = [self parseExpr];
                } else {
                    [args addObject:[self parseExpr]];
                }
                if (![self check:TOKEN_RPAREN]) [self match:TOKEN_COMMA];
            }
            [self expect:TOKEN_RPAREN];
            ASTNode *n = [[ASTNode alloc] initWithType:NODE_CALL];
            [n setField:node forKey:@"func"];
            [n setField:args forKey:@"args"];
            [n setField:kwargs forKey:@"kwargs"];
            node = n;
        } else if ([self check:TOKEN_LBRACKET]) {
            [self advance];
            ASTNode *idx = [self parseExpr];
            [self expect:TOKEN_RBRACKET];
            ASTNode *n = [[ASTNode alloc] initWithType:NODE_SUBSCRIPT];
            [n setField:node forKey:@"value"];
            [n setField:idx forKey:@"index"];
            node = n;
        } else if ([self check:TOKEN_DOT]) {
            [self advance];
            NSString *attr = [self current].value;
            [self advance]; // attribute name
            ASTNode *n = [[ASTNode alloc] initWithType:NODE_ATTRIBUTE];
            [n setField:node forKey:@"value"];
            [n setField:attr forKey:@"attr"];
            node = n;
        } else break;
    }
    return node;
}

- (ASTNode *)parsePrimary {
    Token *t = [self current];
    if (t.type == TOKEN_NUMBER) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_NUMBER];
        [n setField:t.value forKey:@"value"];
        return n;
    }
    if (t.type == TOKEN_STRING) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_STRING];
        [n setField:t.value forKey:@"value"];
        // String concatenation
        while ([self check:TOKEN_STRING]) {
            NSString *extra = [self current].value;
            [self advance];
            n = [[ASTNode alloc] initWithType:NODE_BINOP];
            [n setField:@"+" forKey:@"op"];
            ASTNode *left = [[ASTNode alloc] initWithType:NODE_STRING];
            [left setField:[n fieldForKey:@"value"] ?: @"" forKey:@"value"]; // won't work, fix:
            // Actually just make a new left from previous value
            // Let's just concatenate directly
            NSString *combined = [[t.value stringByAppendingString:@""] stringByAppendingString:extra];
            ASTNode *r = [[ASTNode alloc] initWithType:NODE_STRING];
            [r setField:combined forKey:@"value"];
            return r; // simplified
        }
        return n;
    }
    if (t.type == TOKEN_BOOL_TRUE) { [self advance]; ASTNode *n = [[ASTNode alloc] initWithType:NODE_BOOL]; [n setField:@YES forKey:@"value"]; return n; }
    if (t.type == TOKEN_BOOL_FALSE) { [self advance]; ASTNode *n = [[ASTNode alloc] initWithType:NODE_BOOL]; [n setField:@NO forKey:@"value"]; return n; }
    if (t.type == TOKEN_NONE) { [self advance]; return [[ASTNode alloc] initWithType:NODE_NONE]; }
    if (t.type == TOKEN_IDENTIFIER) {
        [self advance];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_IDENTIFIER];
        [n setField:t.value forKey:@"name"];
        return n;
    }
    if (t.type == TOKEN_LPAREN) {
        [self advance];
        ASTNode *e = [self parseExpr];
        // Could be tuple
        if ([self check:TOKEN_COMMA]) {
            NSMutableArray *elts = [NSMutableArray arrayWithObject:e];
            while ([self match:TOKEN_COMMA] && ![self check:TOKEN_RPAREN]) {
                [elts addObject:[self parseExpr]];
            }
            [self expect:TOKEN_RPAREN];
            ASTNode *n = [[ASTNode alloc] initWithType:NODE_LIST];
            [n setField:elts forKey:@"elts"];
            [n setField:@YES forKey:@"isTuple"];
            return n;
        }
        [self expect:TOKEN_RPAREN];
        return e;
    }
    if (t.type == TOKEN_LBRACKET) {
        [self advance];
        NSMutableArray *elts = [NSMutableArray array];
        while (![self check:TOKEN_RBRACKET] && ![self check:TOKEN_EOF]) {
            [elts addObject:[self parseExpr]];
            if (![self check:TOKEN_RBRACKET]) [self match:TOKEN_COMMA];
        }
        [self expect:TOKEN_RBRACKET];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_LIST];
        [n setField:elts forKey:@"elts"];
        return n;
    }
    if (t.type == TOKEN_LBRACE) {
        [self advance];
        NSMutableArray *keys = [NSMutableArray array];
        NSMutableArray *vals = [NSMutableArray array];
        while (![self check:TOKEN_RBRACE] && ![self check:TOKEN_EOF]) {
            [keys addObject:[self parseExpr]];
            [self expect:TOKEN_COLON];
            [vals addObject:[self parseExpr]];
            if (![self check:TOKEN_RBRACE]) [self match:TOKEN_COMMA];
        }
        [self expect:TOKEN_RBRACE];
        ASTNode *n = [[ASTNode alloc] initWithType:NODE_DICT];
        [n setField:keys forKey:@"keys"];
        [n setField:vals forKey:@"values"];
        return n;
    }
    fprintf(stderr, "Parse error: unexpected token '%s' (type %ld) at line %ld\n",
        t.value.UTF8String, (long)t.type, (long)t.line);
    exit(1);
}

@end
