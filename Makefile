version?=1.0.0
image?=devoptimus/postgres

UID := $(shell id -u)
GID := $(shell id -g)

.PHONY: patch build push all
.DEFAULT_GOAL := all

patch:
	@perl src/patch.pl

build: patch
	@docker build -t $(image):$(version) -f Dockerfile --build-arg=UID=$(UID) --build-arg=GID=$(GID) .
	@docker build -t $(image)-jit:$(version) -f Dockerfile --target=jit --build-arg=UID=$(UID) --build-arg=GID=$(GID) .
	@docker build -t $(image) -f Dockerfile --build-arg=UID=$(UID) --build-arg=GID=$(GID) .
	@docker build -t $(image)-jit -f Dockerfile --target=jit --build-arg=UID=$(UID) --build-arg=GID=$(GID) .

push: build
	@docker push $(image)
	@docker push $(image)-jit
	@docker push $(image):$(version)
	@docker push $(image)-jit:$(version)

all: build push