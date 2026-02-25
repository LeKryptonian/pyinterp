# Benchmark: combined workload
# 1. Fibonacci
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

result = fib(28)
print("fib(28) =", result)

# 2. Sieve of Eratosthenes up to 1000
def sieve(limit):
    primes = []
    is_prime = [True] * (limit + 1)
    is_prime[0] = False
    is_prime[1] = False
    i = 2
    while i <= limit:
        if is_prime[i]:
            primes.append(i)
            j = i * i
            while j <= limit:
                is_prime[j] = False
                j = j + i
        i = i + 1
    return primes

p = sieve(1000)
print("Primes up to 1000:", len(p))

# 3. String processing
words = ["hello", "world", "python", "interpreter", "objective", "c"]
upper_words = []
for w in words:
    upper_words.append(w.upper())
joined = ", ".join(upper_words)
print("Words:", joined)

# 4. List operations
nums = list(range(200))
total = sum(nums)
print("Sum 0-199:", total)

squares = []
for n in nums:
    squares.append(n * n)
print("Sum of squares:", sum(squares))

# 5. Dictionary usage
freq = {}
sentence = "the quick brown fox jumps over the lazy dog the fox"
for word in sentence.split():
    if word in freq:
        freq[word] = freq[word] + 1
    else:
        freq[word] = 1
print("Word 'the' count:", freq["the"])
print("Word 'fox' count:", freq["fox"])

# 6. Class usage
class Counter:
    def __init__(self):
        self.count = 0

    def increment(self):
        self.count = self.count + 1

    def value(self):
        return self.count

c = Counter()
i = 0
while i < 100:
    c.increment()
    i = i + 1
print("Counter:", c.value())

print("Done.")
