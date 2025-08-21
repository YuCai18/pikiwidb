CXX = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2
TARGET = hashmap
SOURCE = hashmap.cpp

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SOURCE)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all run clean