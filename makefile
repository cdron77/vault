TARGET=vault
PREFIX?=/usr/local

install:
	@mkdir -p $(PREFIX)/bin
	@cp -f $(TARGET).sh $(PREFIX)/bin/$(TARGET)
	@chmod 755 $(PREFIX)/bin/$(TARGET)
