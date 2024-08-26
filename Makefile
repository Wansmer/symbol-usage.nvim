parallel-test:
	nvim --headless -u tests/minimal.lua -c "PlenaryBustedDirectory tests/parallel/ {minimal_init = 'tests/minimal.lua'}"

sequential-test:
	nvim --headless -u tests/minimal.lua -c "PlenaryBustedDirectory tests/sequential/ {minimal_init = 'tests/minimal.lua', sequential = true}"

test:
	make parallel-test && make sequential-test
