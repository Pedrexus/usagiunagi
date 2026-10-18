.PHONY : generate

generate:
	protoc \
		--experimental_allow_proto3_optional \
		--swift_out=../Sources/WaniKaniAPI \
		--swift_opt=Visibility=Public \
		wanikani_api.proto
