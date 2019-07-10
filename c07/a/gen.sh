 #!/bin/bash

buildDir='./build'

#generate disk file
echo '尝试删除旧的磁盘'
rm /home/kevin/development/tools/hd60M.img
echo '尝试创建模拟磁盘'
/usr/bin/bximage -hd -mode="flat" -size=60 -q /home/kevin/development/tools/hd60M.img

echo '开始清空中间文件'
for fileName in `ls $buildDir`
do
    echo '准备删除文件：'$fileName
    `rm $buildDir/$fileName`
done

echo '尝试编译mbr程序，并写入mbr到模拟磁盘中'
nasm -i boot/include/ -o $buildDir/mbr.bin boot/mbr.S && dd if=$buildDir/mbr.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=1 conv=notrunc
echo '尝试编译loader程序，并写入loader到模拟磁盘中'
nasm -i boot/include/ -o $buildDir/loader.bin boot/loader.S && dd if=$buildDir/loader.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=4 seek=2 conv=notrunc

echo '尝试编译print.S汇编文件'
# 因为这个编译后的文件，最后是要和C语言的目标文件进行链接的，所以要指定elf格式，便于链接
nasm -f elf -o $buildDir/print.o lib/kernel/print.S

echo '尝试编译kernel.S汇编文件'
nasm -f elf -o $buildDir/kernel.o kernel/kernel.S


echo '尝试编译main.c C语言程序'
# 和书上不同的是增加了lib目录，作为头文件的搜索地址。不然好像stdint.h 会到系统路径下找
gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 -c -o $buildDir/main.o kernel/main.c 

echo '尝试编译interrupt.c源文件'
gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 -c -o $buildDir/interrupt.o kernel/interrupt.c

echo '尝试编译init.c源文件'
gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 -c -o $buildDir/init.o kernel/init.c

#-m32 选项指定gcc生成32位的ELF目标文件。因为之前生成的64位目标文件的运行有些异常，这里手动指定了32位格式
#-m elf_i386也是手动指定ld链接器，进行32位目标文件的链接
echo '通过32位模式，编译和链接kernel程序'
ld -m elf_i386 -Ttext 0xc0001500 -e main -o $buildDir/kernel.bin  $buildDir/main.o $buildDir/init.o $buildDir/interrupt.o \
    $buildDir/print.o $buildDir/kernel.o



echo 'kernel程序写入磁盘......'
dd if=$buildDir/kernel.bin of=/home/kevin/development/tools/bochs/hd60M.img bs=512 count=200 seek=9 conv=notrunc
