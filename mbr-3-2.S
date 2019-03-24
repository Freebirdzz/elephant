;主引导程序
;----------------------------------------------------
%include "boot.inc"     ;类似于C语言中的宏定义包含

SECTION MBR vstart=0x7c00
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp, 0x7c00
    mov ax, 0xb800
    mov gs, ax

;清屏利用0x06号功能，上卷全部行，则可清屏(参考真象还原61页)
    mov ax, 0x600
    mov bx, 0x700
    mov cx, 0
    mov dx, 0x184f

    int 0x10

    mov byte [gs:0x00], '1'
    mov byte [gs:0x01], 0xA4 ;A表示绿色背景闪烁，4表示前景色为红色
    
    mov byte [gs:0x02],' '
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04], 'M'
    mov byte [gs:0x05], 0xA4

    mov byte [gs:0x06], 'B'
    mov byte [gs:0x07], 0xA4

    mov byte [gs:0x08], 'R'
    mov byte [gs:0x09], 0xA4


    mov eax, LOADER_START_SECTOR    ;起始扇区lba地址
    mov bx, LOADER_BASE_ADDR        ;写入内存的地址
    mov cx, 1                       ;待读入的扇区数；只读入一个扇区的磁盘内容
    call rd_disk_m_16               ;以下读取程序的起始部分（一个扇区）

    jmp LOADER_BASE_ADDR            ;跳转到磁盘中读取出的程序地址开始执行（loader程序）

;----------------------------------------------------------------------------------------------------
;功能：读取磁盘n个扇区
rd_disk_m_16:
;----------------------------------------------------------------------------------------------------

    mov esi, eax    ;备份eax
    mov di,cx       ;备份cx

;读写硬盘
;第一步：设置要读取的扇区数
    mov dx, 0x1f2
    mov al, cl
    out dx, al      ;读取的扇区数

    mov eax, esi    ;恢复ax

;第二步：将LBA的地址存入0x1f3 - 0x1f6
    mov dx, 0x1f3   ;LBA地址的7-0位写入端口0x1f3
    out dx, al

    mov cl, 8       ;LBA地址15 - 8 位写入端口0x1f4
    shr eax, cl     ;逻辑右移指令，
    mov dx, 0x1f4
    out dx, al

    shr eax, cl     ;LBA地址23-16 写入端口0x1f5
    mov dx, 0x1f5
    out dx, al

    shr eax, cl
    and al, 0x0f    ;lba第24-27位
    or al, 0xe0     ;设置 7 - 4位为1110， 表示lba模式
    mov dx, 0x1f6
    out dx, al

;第三步：向0x1f7端口写入读命令， 0x20
    mov dx, 0x1f7
    mov al, 0x20
    out dx, al

;第四步：检测硬盘状态
    .not_ready:
    ;同一端口，写时表示写入命令字，读时表示读入硬盘状态
    nop     ;表示空仓操作，什么都不做，相当于sleep了一小段时间
    in al, dx
    and al, 0x88    ;第4位为1表示硬盘控制器已经准备好数据传输

    cmp al, 0x08    
    jnz .not_ready      ;若未准备好，继续等 jnz是一个跳转指令，会结合上一步comp的结果决定

;第五步：从0x1f0端口读数据
    mov ax, di
    mov dx, 256
    mul dx          ;di为要读取的扇区数，一个扇区有512字节，每次读入一个字；共需要di*256次
    mov cx, ax

    mov dx, 0x1f0
.go_on_read:
    in ax, dx
    mov [bx], ax
    add bx, 2
    loop .go_on_read
    ret             ;函数执行结束


    times 510-($-$$) db 0
    db 0x55, 0xaa   ;BIOS识别MBR程序的标志
