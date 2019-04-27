%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
jmp loader_start

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
    
    ;total_mem_bytes 用于保存内存容量，以字节为单位
    ;当前loader.bin文件头0x200字节
    ;loader.bin的加载地址是0x900
    ;故total_meme_bytes内存中的地址是0xb00
    total_mem_bytes dd 0



    ;选择子一共是一个2字节16位的结构。其中的高13位表示段描述符索引下标。低三位表示TI位和RPL特权级。i
    ;十六进制的0001，一共是16位，右移3位以后的结果就是0000000000001000（1前面12个零，1后面3个零。3个零用于后面累加的TI和RPL）
    ;然后累加TI值和RPL值
    SELECTOR_CODE   equ    (0x0001<<3) + TI_GDT + RPL0     ;代码段的选择子。相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT +RPL0。GDT这个数组的下标1位置
    SELECTOR_DATA   equ    (0x0002<<3) + TI_GDT + RPL0     ;数组下标2
    SELECTOR_VIDEO  equ    (0x0003<<3) + TI_GDT + RPL0     ;数组下标3
    
    ;一下是gdt的指针（GDTR）。前2字节是gdt界限，后4字节是gdt起始地址（32位哦！）
    gdt_ptr    dw    GDT_LIMIT
                dd    GDT_BASE
    
    ;人工对齐：total_mem_types4 + gdt_ptr6 + ards_buf244 + ards_nr2，共256字节
    ards_buf times 244 db 0
    ards_nr dw 0    ;用于记录ARDS结构体数量
    ;------------------------------------------------- GDT以及其内部描述符构造结束----------------------------------------------

    
    loader_start:
    
    ;int 15h eax = 000E820h, edx = 534D4150h ('SMAP')获取内存布局
    xor ebx, ebx                ;第一次调用时，ebx值要为0
    mov edx, 0x534d4150         ;这个值是规定！参考180页说明。edx只赋值一次，循环体中不会改变
    mov di, ards_buf            ;ards结构缓冲

.e820_meme_get_loop:            ;循环获取每个ards内存范围描述结构
    mov eax, 0x0000e820         ;执行int 0x15后，eax值为0x534d4150！所以，每次执行int前都要更新为子功能号
    mov ecx, 20
    int 0x15
    jc .e820_failed_so_try_e801 ; jc = jump if carry.表示：当运算产生进位标志时，即CF=1时，跳转到目标程序处。（如果e820调用失败，CF的值会是1）
    add di, ecx                 ;使di增加20字节，指向缓冲区中新的ards结构位置
    inc word [ards_nr]          ;记录ards数量。inc表示对后面的变量进行自增，对于存储单元，需要用BYTE PTR或者WORD PTR说明是字节还是字操作。
    cmp ebx, 0                  ;若ebx为0且cf不为1，说明ards全部返回；当前已经是最后一个
    
    ;----------------------------------------------------------------------
    ;INT 0x10       功能号：0x13        功能描述：打印字符串
    ;----------------------------------------------------------------------
    mov sp, LOADER_BASE_ADDR
    mov bp, loadermsg               ;ES：BP = 字符串地址
    mov cx, 17                      ;CX = 字符串长度
    mov ax, 0x1301                  ;AH = 13， AL = 01h
    mov bx, 0x001f                  ;页号为0（BH=0）蓝底粉红色（BL = 1fh)
    mov dx, 0x1800
    int 0x10                        ;10h 号中断

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

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA                    ;ds寄存器，保存数据段选择子
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'

    jmp $
