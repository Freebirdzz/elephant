 #!/bin/bash


#generate disk file
echo '尝试删除旧的磁盘'
rm /home/kevin/development/tools/hd60M.img
echo '尝试创建模拟磁盘'
/usr/bin/bximage -hd -mode="flat" -size=60 -q /home/kevin/development/tools/hd60M.img

echo '尝试写入mbr到模拟磁盘中'
nasm -i include/ -o mbr.bin mbr.S && dd if=./mbr.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=1 conv=notrunc
echo '尝试写入loader到模拟磁盘中'
nasm -i include/ -o loader.bin loader.S && dd if=./loader.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=4 seek=2 conv=notrunc
#-m32 选项指定gcc生成32位的ELF目标文件。因为之前生成的64位目标文件的运行有些异常，这里手动指定了32位格式
#-m elf_i386也是手动指定ld链接器，进行32位目标文件的链接
echo '通过32位模式，编译和链接kernel程序，并写入到模拟磁盘中'
gcc -m32 -c -o kernel/main.o kernel/main.c && ld -m elf_i386 kernel/main.o -Ttext 0xc0001500 -e main -o kernel/kernel.bin && dd if=kernel/kernel.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=200 seek=9 conv=notrunc
