buildtest:
	luau --compile=binary test.luau > test.out
	luvit build.lua
	luau --compile=text test.luau > test.txt

run: buildtest
	luvit QLVM/main.lua
