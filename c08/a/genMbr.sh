
 #!/bin/bash

buildDir='./build'

#generate disk file
echo '尝试删除旧的磁盘'
rm /home/kevin/development/tools/bochs/hd60M.img
echo '尝试创建模拟磁盘'
/usr/bin/bximage -hd -mode="flat" -size=60 -q /home/kevin/development/tools/bochs/hd60M.img

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

