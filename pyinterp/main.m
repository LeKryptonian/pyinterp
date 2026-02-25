#import <Foundation/Foundation.h>
#import "include/Lexer.h"
#import "include/Parser.h"
#import "include/Interpreter.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: pyinterp <script.py>\n");
            return 1;
        }

        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSError *err = nil;
        NSString *source = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
        if (!source) {
            fprintf(stderr, "Error reading file '%s': %s\n", argv[1], err.localizedDescription.UTF8String);
            return 1;
        }

        Lexer *lexer = [[Lexer alloc] initWithSource:source];
        NSArray<Token *> *tokens = [lexer tokenize];

        Parser *parser = [[Parser alloc] initWithTokens:tokens];
        NSArray<ASTNode *> *ast = [parser parse];

        Interpreter *interp = [[Interpreter alloc] init];
        [interp runStatements:ast];
    }
    return 0;
}
