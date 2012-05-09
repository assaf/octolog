default : test
.PHONY : publish setup test

# Setup everything
setup :
	npm install

# Publish new release to NPM
publish : 
	npm publish
	git push

