username?=devoptimus
version?=0.0.1

build:
	# docker build -t devoptimus/postgres:$(version) --target=postgres .
	# docker build -t devoptimus/postgres-jit:$(version) --target=jit .
	docker build -t devoptimus/postgres --target=postgres .
	docker build -t devoptimus/postgres-jit --target=jit .

push: build
	docker login -u $(username)
	
	# docker push devoptimus/postgres:$(version)
	# docker push devoptimus/postgres-jit:$(version)
	docker push devoptimus/postgres
	docker push devoptimus/postgres-jit

