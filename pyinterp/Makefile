CC       = clang
CFLAGS   = -ObjC -fobjc-arc -O2 -Wall -Wno-unused-variable \
           -framework Foundation \
           -I.
SRCS     = main.m \
           src/Lexer.m \
           src/ASTNode.m \
           src/Parser.m \
           src/Interpreter.m
TARGET   = pyinterp

.PHONY: all clean test

all: $(TARGET)
	@echo ""
	@echo "✅  Build successful → ./$(TARGET)"
	@echo ""

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

clean:
	rm -f $(TARGET)

test: $(TARGET)
	@echo "── Running test suite ──────────────────────────────────────"
	@./$(TARGET) tests/hello.py
	@./$(TARGET) tests/fibonacci.py
	@./$(TARGET) tests/oop.py
	@echo "── All tests passed ────────────────────────────────────────"
