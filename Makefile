# Convenience targets: make setup | make verify | make q32sup
.PHONY: setup verify q32sup clean-restore
setup:
	scripts/setup.sh
verify:
	scripts/verify.sh
q32sup:
	gcc -O2 -Wall -o qemu10/q32sup src/q32sup.c
clean-restore:
	rm -rf qemu10/usr qemu/usr sysroot32/root wine32/wine-11.21-x86 wineprefix32 wow64/wine-11.21-amd64-wow64 wow64/wine-11.21-staging-amd64-wow64
	@echo "extracted trees removed; re-run scripts/setup.sh to restore"
