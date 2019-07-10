%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

;---------------------------------------- 构建gdt以及其内部描述符开始 ------------------------------------
;GDT本质上是个数组，数组中的每个元素都是一个段描述符。每个段描述符的大小是8字节，64位。也就是16个十六进制的数字
;因为GDT这个数组中，第一个元素（也就是小标0）是不可用的。原因参考书中156页说明，所以有一个GDT_BASE元素
    GDT_BASE:   dd    0x00000000
                dd    0x00000000
    
    CODE_DESC:  dd    0x0000FFFF
                dd    DESC_CODE_HIGH4
    
    DATA_STACK_DSC: dd    0x0000FFFF
                    dd    DESC_DATA_HIGH4
    
    VIDEO_DESC: dd    0x80000007;limit=(0xbffff-0xb8000)/4k=0x7
                dd    DESC_VIDEO_HIGH4
    
    GDT_SIZE    equ    $ - GDT_BASE                
    GDT_LIMIT   equ    GDT_SIZE - 1
    times 60 dq 0   ;此处预留60个描述符空位
    ;选择子一共是一个2字节16位的结构。其中的高13位表示段描述符索引下标。低三位表示TI位和RPL特权级。i
    ;十六进制的0001，一共是16位，右移3位以后的结果就是0000000000001000（1前面12个零，1后面3个零。3个零用于后面累加的TI和RPL）
    ;然后累加TI值和RPL值
    SELECTOR_CODE   equ    (0x0001<<3) + TI_GDT + RPL0     ;代码段的选择子。相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT +RPL0。GDT这个数组的下标1位置
    SELECTOR_DATA   equ    (0x0002<<3) + TI_GDT + RPL0     ;数组下标2
    SELECTOR_VIDEO  equ    (0x0003<<3) + TI_GDT + RPL0     ;数组下标3
    
    ;total_mem_bytes 用于保存内存容量，以字节为单位
    ;当前loader.bin文件头0x200字节
    ;loader.bin的加载地址是0x900
    ;故total_meme_bytes内存中的地址是0xb00
    total_mem_bytes dd 0

    ;一下是gdt的指针（GDTR）。前2字节是gdt界限，后4字节是gdt起始地址（32位哦！）
    gdt_ptr    dw    GDT_LIMIT
                dd    GDT_BASE
    
    ;人工对齐：total_mem_types4 + gdt_ptr6 + ards_buf244 + ards_nr2，共256字节
    ards_buf times 244 db 0
    ards_nr dw 0    ;用于记录ARDS结构体数量
    ;------------------------------------------------- GDT以及其内部描述符构造结束----------------------------------------------

    
    loader_start:
    
;-------------------------- int 15h eax = 000E820h, edx = 534D4150h ('SMAP')获取内存布局 ----------------------------------------
    xor ebx, ebx                ;第一次调用时，ebx值要为0
    mov edx, 0x534d4150         ;这个值是规定！参考180页说明。edx只赋值一次，循环体中不会改变
    mov di, ards_buf            ;ards结构缓冲

.e820_mem_get_loop:            ;循环获取每个ards内存范围描述结构
    mov eax, 0x0000e820         ;执行int 0x15后，eax值为0x534d4150！所以，每次执行int前都要更新为子功能号
    mov ecx, 20
    int 0x15
    jc .e820_failed_so_try_e801 ; jc = jump if carry.表示：当运算产生进位标志时，即CF=1时，跳转到目标程序处。（如果e820调用失败，CF的值会是1）
    add di, cx                 ;使di增加20字节，指向缓冲区中新的ards结构位置
    inc word [ards_nr]          ;记录ards数量。inc表示对后面的变量进行自增，对于存储单元，需要用BYTE PTR或者WORD PTR说明是字节还是字操作。
    cmp ebx, 0                  ;若ebx为0且cf不为1，说明ards全部返回；当前已经是最后一个

    jnz .e820_mem_get_loop      ;jnz指令, if(ZF!=0)则跳转

    ;在所有ards结构中，找出（base_add_low + length_low)的最大值，即内存的容量
    mov cx, [ards_nr]

    ;遍历每一个ards结构体，循环次数是ards的数量
    mov ebx, ards_buf
    xor edx, edx                ;edx为最大的内存容量，在此先清零

.find_max_mem_area:
    mov eax, [ebx]              ;base_add_low
    add eax, [ebx+8]            ;length_low
    add ebx, 20                 ;指向缓冲区下一个ards结构
    cmp edx, eax
    
    jge .next_ards              ;if (ZF >= 0)则跳转
    mov edx, eax                ;edx为总内存大小

.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok


;--------------------------- int 15h ax=E801h 获取内存大小，最大支持4G -----------------------------------
;返回后，ax cx值一样，以KB为单位，bx dx值一样，以64K为单位
;在ax和cx寄存器中为低16MB，在bx和dx寄存器中为16MB到4GB
.e820_failed_so_try_e801:
    mov ax, 0xe801
    int 0x15
    jc .e801_failed_so_try88        ;如果当前方法失败，尝试0x88方法

    ;1 先算出低15MB的内存
    ;ax和cx中是以KB为单位的内存数量，将其转换为以byte为单位
    mov cx, 0x400                   ;cx和ax值一样，cx用作乘数。表示值：1024
    mul cx
    shl edx, 16
    and eax, 0x0000FFFF
    or edx, eax
    add edx, 0x100000               ;ax只是15MB，所以要加1MB
    mov esi, edx                    ;先把低15MB的内存容量存入esi寄存器备份

    ;2 再将16MB以上的内存转换为byte单位
    ;寄存器bx和dx中是以64KB为单位的内存数量
    xor eax, eax
    mov ax, bx
    mov ecx, 0x10000                ;十进制64KB
    mul ecx                         ;32位乘法，默认的被乘数是eax，结果为64位，高32位存入edx，低32位存入eax

    add esi, eax
    mov edx, esi                    ;edx位总内存大小
    jmp .mem_get_ok

;------------------------------- int 15h ah=0x88 获取内存大小，只能获取64MB之内
.e801_failed_so_try88:
    mov ah, 0x88
    int 0x15
    jc .error_hlt
    and eax, 0x0000FFFF

    mov cx, 0x400
    mul cx
    shl edx, 16
    or edx, eax
    add edx, 0x100000

.mem_get_ok:
    mov eax, 0x4422
    mov [total_mem_bytes], edx  ;将内存换位byte单位后写入total_mem_bytes处


;------------------------- 准备进入保护模式 ------------------------------
;1. 打开A20
;2. 加载GDT
;3. 将cr0 的 pe位 置1

    ;---------------------- 打开A20 --------------------------
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

    ;---------------------- 加载GDT --------------------------
    lgdt [gdt_ptr]


    ;---------------------- cr0第0位置1 ----------------------
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp dword SELECTOR_CODE:p_mode_start    ;刷新流水线


.error_hlt:                 ;这个东西的位置非常关键哦！！！！！！！！！！！
    hlt
    mov ax, 0x999

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA                    ;ds寄存器，保存数据段选择子
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax


    ;-------------------------------------  加载kernel  ------------------------------------------
    mov eax, KERNEL_START_SECTOR    ;kernel.bin 所在的扇区号
    mov ebx, KERNEL_BIN_BASE_ADDR   ;从磁盘读出后，写入到ebx指定的地址
    mov ecx, 200                    ;读入的扇区数

    call rd_disk_m_32
    ;创建页目录以及页表并初始化内存位图
    call setup_page

    ;要将描述符表地址以及偏移量写入内存gdt_ptr，一会儿用新地址重新加载
    sgdt [gdt_ptr]      ;存储到原来gdt所有的位置
    
    ;将gdt描述符中视频段描述符中的段基址+0xc0000000
    mov ebx, [gdt_ptr +2]
    or dword [ebx + 0x18 + 4], 0xc0000000
    ;视频段是第三个段描述符，每个描述符是8字节，所以0x18

    ;将gdt的基址加上 0xc0000000 使其成为内核所在的高地址
    add dword [gdt_ptr + 2], 0xc0000000

    add esp, 0xc0000000    ;将栈指针同样映射得到内核地址

    ;把页目录地址赋值给cr3
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax

    ;打开cr0的pg位（第31位）
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ;在开启分页后，用gdt新的地址重新加载
    lgdt [gdt_ptr]

    mov byte [gs:160], 'V'      ;视频段基址已经被更新，用字符V表示virtual addr
    mov byte [gs:162], 'i'
    mov byte [gs:164], 'r'
    mov byte [gs:166], 't'
    mov byte [gs:168], 'u'
    mov byte [gs:170], 'a'
    mov byte [gs:172], 'l'
    
    jmp SELECTOR_CODE:enter_kernel      
enter_kernel:
    mov byte [gs:320], 'k'      ;视频段基址已经被更新，用字符V表示virtual addr
    mov byte [gs:322], 'e'
    mov byte [gs:324], 'r'
    mov byte [gs:326], 'n'
    mov byte [gs:328], 'a'
    mov byte [gs:330], 'l'
    
    mov byte [gs:480], 'w'
    mov byte [gs:482], 'h'
    mov byte [gs:484], 'i'
    mov byte [gs:486], 'l'
    mov byte [gs:488], 'e'
    mov byte [gs:490], '('
    mov byte [gs:492], '1'
    mov byte [gs:494], ')'
    mov byte [gs:496], ';'
    call kernel_init
    mov esp, 0xc009f000
    jmp KERNEL_ENTRY_POINT      ;用地址0x1500访问测试
    
;------------------------------ 创建页目录以及页表 ----------------------------------
setup_page:
    ;先把页目录占用的空间逐清零
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0
    inc esi
    loop .clear_page_dir

    ;开始创建页目录项（PDE）
.create_pde:           ; 创建Page Directory Entry
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000     ;此时 eax为第一个页表的位置及属性
    mov ebx, eax        ;此处为ebx赋值，为.create_pte做准备，ebx为基址
    
    ;下面将页目录项0和0xc00都存为第一个页表的地址，每个页表表示4MB内存
    ;这样 0xc03fffff以下的地址和 0x003fffff以下的地址都指向相同的页表。
    ;这是为降低至映射为内核地址做准备
    or eax, PG_US_U | PG_RW_W | PG_P
    ;页目录项的属性RW和P位为1，US为1，表示用户属性，所有特权级别都可以访问
    mov [PAGE_DIR_TABLE_POS + 0x0], eax         ;第一个目录项

    mov [PAGE_DIR_TABLE_POS + 0xc00], eax
    ;一个页表占用4字节
    ;0xc00，表示第768个页表所占用的目录项，0xc00以上的目录项用于内核空间
    ;也就是页表的0xc0000000 ~ 0xffffffff共计1G的空间属于内核
    ;0x00000000 ~ 0xbfffffff 共3G的空间属于用户进程
    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax        ;使最后一个目录项指向页目录表自己的地址

;下面创建页表项（PTE）
    mov ecx, 256        ;1M低端内存 每页4k = 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P   ;属性为7，US=1， RW=1， P=1
.create_pte:                ;创建page table entry
    mov [ebx + esi*4], edx
    ;此时的ebx已经在上面通过eax赋值为0x101000,也就是第一个页表的地址
    add edx, 4096
    inc esi
    loop .create_pte

;创建内核其他页表的PDE
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000     ;此时eax为第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P    ;页目录的属性US、RW、P位都为1
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254            ;范围为第769 ~ 1022 的所有目录项数量
    mov esi, 769
.create_kernel_pde:
    mov [ebx + esi*4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde
    ret


    ;----------------------------  将kernel.bin 中的 segment 拷贝到编译的地址  -------------------------------
kernel_init:
    xor eax, eax
    xor ebx, ebx    ;ebx记录程序头表地址
    xor ecx, ecx    ;cx记录程序头表中的program header数量
    xor edx, edx    ;dx记录program header尺寸，即e_phentsize

    mov dx, [KERNEL_BIN_BASE_ADDR + 42]     ;偏移文件42字节处的属性是e_phentsize, 表示program header大小
    mov ebx, [KERNEL_BIN_BASE_ADDR + 28]    ;偏移文件开始部分呢28字节的地方是e_phoff
    
    add ebx, KERNEL_BIN_BASE_ADDR
    mov cx, [KERNEL_BIN_BASE_ADDR + 44]    ;偏移那件开始部分44字节的地方时e_phnum,表示有几个program header

.each_segment:
    cmp byte [ebx + 0], PT_NULL     ;若p_type等于PT_NULL，说明此program header未使用
    je .PTNULL

    ;为函数memcpy压入参数，参数是从右往左依次压入
    ;函数原型类似于memcpy(dst, src, size)
    push dword [ebx + 16]
    ;program header中偏移16字节的地方时p_filesz
    ;压入函数memcpy的第三个参数：size

    mov eax, [ebx + 4]  ;距离程序头偏移量为4字节的位置是p_offset
    add eax, KERNEL_BIN_BASE_ADDR
    ;加上kernel.bin被加载到的物理地址，eax为该段的物理地址
    push eax        ;压入函数memcpy的第二个参数：原地址
    push dword [ebx + 8]    ;压入函数memcpy的第一个参数，目的地址偏移程序头8字节位置的是p_vaddr，也就是目的地址

    call mem_cpy            ;调用memcpy完成段复制
    add esp, 12             ;清理栈中压入的三个参数

.PTNULL:
    add ebx, edx        ;edx为program header大小，即e_phentsize  在此ebx指向下一个program header
    loop .each_segment
    ret

;--------------------- 逐字节拷贝 mem_cpy(dst, src, size) ----------------------------------------
;输入：栈中三个参数（dst, src, size)
;输出：无
;-------------------------------------------------------------------------------------------------
mem_cpy:
    cld
    push ebp
    mov ebp, esp
    push ecx        ;rep指令用到了ecx，但ecx对于外层段的循环还有用，所以先入栈备份一下

    mov edi, [ebp + 8]      ;dst
    mov esi, [ebp + 12]     ;src
    mov ecx, [ebp + 16]     ;size
    rep movsb               ;逐个字节拷贝

    ;恢复环境
    pop ecx
    pop ebp
    ret



;----------------------------------------------------------------------------------------------------
;功能：读取磁盘n个扇区
rd_disk_m_32:
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
    mov [ebx], ax
    add ebx, 2
    loop .go_on_read
    ret             ;函数执行结束
