FILES := test-library.dylan \
	 entity-pass.dylan \
	 html-xform.dylan \
	 xml-test.dylan

xml-test: $(FILES)
	d2c -L .. -L ../../anaphora -L ../../meta -L xml-test.lid

clean:
	rm *.o *.c *~ cc-*.mak *.a xml-test

