class Animal:
    def __init__(self, name, sound):
        self.name = name
        self.sound = sound

    def speak(self):
        print(self.name + " says " + self.sound)

class Dog:
    def __init__(self, name):
        self.name = name

    def speak(self):
        print(self.name + " says Woof!")

    def fetch(self, item):
        print(self.name + " fetches the " + item)

dog = Dog("Rex")
dog.speak()
dog.fetch("ball")

cat = Animal("Whiskers", "Meow")
cat.speak()

animals = [Dog("Buddy"), Animal("Tweety", "Tweet"), Dog("Max")]
for a in animals:
    a.speak()
