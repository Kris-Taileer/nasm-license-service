; minimal TCP service
; nasm -f elf64 main.asm -o main.o && ld main.o -o service -e _start
default rel
%define PORT        4444
%define BACKLOG     5
%define AF_INET     2
%define SOCK_STREAM 1

section .data
    sockaddr_in:
        dw AF_INET          ; sin_family, little-endian
        db 0x11, 0x5C       ; sin_port = 4444 BigEndiAN CUZ IT'S A PORT
        db 0, 0, 0, 0       ; sin_addr = INADDR_ANY (must accept non-loopback traffic in a container)
        dq 0                ; paddin

    menu:
        db "=== License Service ===", 10
        db "REGISTER <name>", 10
        db "LOGIN <name>", 10
        db "LICENSE", 10
    menu_len: equ $ - menu

    prompt: db "> "
    prompt_len: equ $ - prompt

    cmd_register: db "REGISTER"
    cmd_register_len: equ $ - cmd_register

    cmd_login: db "LOGIN"
    cmd_login_len: equ $ - cmd_login

    cmd_license: db "LICENSE"
    cmd_license_len: equ $ - cmd_license

    msg_register: db "REGISTER: account created", 10
    msg_register_len: equ $ - msg_register

    msg_login: db "LOGIN: ok", 10
    msg_login_len: equ $ - msg_login

    msg_login_fail: db "invalid credentials", 10
    msg_login_fail_len: equ $ - msg_login_fail

    msg_not_logged_in: db "login first", 10
    msg_not_logged_in_len: equ $ - msg_not_logged_in

    msg_unknown: db "unknown option", 10
    msg_unknown_len: equ $ - msg_unknown

    db_path: db "accounts.db", 0

    hex_digits_lo: db "0123456789abcdef"

section .bss
    client_buf: resb 256
    name_buf: resb 32
    password_buf: resb 32
    license_buf: resb 32
    file_buf: resb 96
    logged_in: resb 1
    session_name: resb 32
    session_license: resb 32
    license_hex: resb 65

section .text
    global _start
    extern license_generate

_start:
    ; socket(AF_INET, SOCK_STREAM, 0)
    mov rax, 41
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall  ; x = socket(1, 2, 3);   if x  --  0
    cmp rax, 0
    jl fail
    mov r12, rax             ; r12 = listen_fd

    ; setsockopt(fd, SOL_SOCKET=1, SO_REUSEADDR=2, &val=1, 4)
    mov rax, 54
    mov rdi, r12
    mov rsi, 1
    mov rdx, 2
    mov r10, reuse_val
    mov r8, 4
    syscall

    ; bind(fd, &sockaddr_in, 16)
    mov rax, 49
    mov rdi, r12
    mov rsi, sockaddr_in
    mov rdx, 16
    syscall
    cmp rax, 0
    jl fail

    ; listen(fd, BACKLOG)
    mov rax, 50
    mov rdi, r12
    mov rsi, BACKLOG
    syscall
    cmp rax, 0
    jl fail

accept_loop:
    ; accept(fd, NULL, NULL)
    mov rax, 43
    mov rdi, r12
    mov rsi, 0
    mov rdx, 0
    syscall
    cmp rax, 0
    jl accept_loop
    mov r13, rax             ; r13 = client_fd

    ; fork()
    mov rax, 57
    syscall
    cmp rax, 0
    je child
    jl .close_parent

.close_parent:
    mov rax, 3
    mov rdi, r13
    syscall
    jmp accept_loop

child:
    ; write(client_fd, msg, msg_len) MENU
    mov rax, 1
    mov rdi, r13
    mov rsi, menu
    mov rdx, menu_len
    syscall
client_loop:
    ; write(client_fd, prompt, prompt_len)
    mov rax, 1
    mov rdi, r13
    mov rsi, prompt
    mov rdx, prompt_len
    syscall
    ; read(client_fd, msg, msg_len)
    mov rax, 0
    mov rdi, r13
    mov rsi, client_buf
    mov rdx, 256
    syscall
    cmp rax, 0
    jle close_client
    mov r14, rax

    lea rdi, [client_buf]
    lea rsi, [cmd_register]
    mov rdx, cmd_register_len
    call strcmp_prefix
    jne .not_register
    call is_word_boundary
    je reg
.not_register:
    lea rdi, [client_buf]
    lea rsi, [cmd_login]
    mov rdx, cmd_login_len
    call strcmp_prefix
    jne .not_login
    call is_word_boundary
    je login
.not_login:
    lea rdi, [client_buf]
    lea rsi, [cmd_license]
    mov rdx, cmd_license_len
    call strcmp_prefix
    jne garbage
    call is_word_boundary
    je license
    jmp garbage

reg:
    lea rdi, [client_buf + cmd_register_len + 1]
    mov rsi, r14
    sub rsi, cmd_register_len
    sub rsi, 1
    lea rdx, [name_buf]
    call parse_word
    add rdi, rax
    sub rsi, rax
    lea rdx, [password_buf]
    call parse_word

    lea rdi, [name_buf]
    lea rsi, [license_buf]
    call license_generate

    call db_append_account

    mov rax, 1
    mov rdi, r13
    mov rsi, msg_register
    mov rdx, msg_register_len
    syscall
    jmp client_loop

login:
    lea rdi, [client_buf + cmd_login_len + 1]
    mov rsi, r14
    sub rsi, cmd_login_len
    sub rsi, 1
    lea rdx, [name_buf]
    call parse_word
    add rdi, rax
    sub rsi, rax
    lea rdx, [password_buf]
    call parse_word

    call db_find_account
    cmp rax, 1
    jne .login_fail

    mov byte [logged_in], 1
    xor rcx, rcx
.copy_session:
    cmp rcx, 32
    jge .login_ok
    mov al, [name_buf + rcx]
    mov [session_name + rcx], al
    inc rcx
    jmp .copy_session

.login_ok:
    mov rax, 1
    mov rdi, r13
    mov rsi, msg_login
    mov rdx, msg_login_len
    syscall
    jmp client_loop

.login_fail:
    mov rax, 1
    mov rdi, r13
    mov rsi, msg_login_fail
    mov rdx, msg_login_fail_len
    syscall
    jmp client_loop

license:
    cmp byte [logged_in], 1
    jne .not_logged_in

    lea rdi, [session_license]
    lea rsi, [license_hex]
    mov rdx, 32
    call hex_encode
    mov byte [license_hex + 64], 10

    mov rax, 1
    mov rdi, r13
    mov rsi, license_hex
    mov rdx, 65
    syscall
    jmp client_loop

.not_logged_in:
    mov rax, 1
    mov rdi, r13
    mov rsi, msg_not_logged_in
    mov rdx, msg_not_logged_in_len
    syscall
    jmp client_loop

garbage:
    mov rax, 1
    mov rdi, r13
    mov rsi, msg_unknown
    mov rdx, msg_unknown_len
    syscall
    jmp client_loop

strcmp_prefix:
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    je .match
    mov al, [rdi + rcx]
    cmp al, [rsi + rcx]
    jne .nomatch
    inc rcx
    jmp .loop
.match:
    ret
.nomatch:
    ret

is_word_boundary:
    mov al, [rdi + rdx]
    cmp al, ' '
    je .match
    cmp al, 10
    ret
.match:
    cmp al, al
    ret

parse_word:
    xor rcx, rcx
.loop:
    cmp rcx, rsi
    jge .done_noeof
    cmp rcx, 31
    jge .done_noeof
    mov al, [rdi + rcx]
    cmp al, ' '
    je .done_delim
    cmp al, 10
    je .done_delim
    mov [rdx + rcx], al
    inc rcx
    jmp .loop
.done_delim:
    call pad_zero
    mov rax, rcx
    inc rax
    ret
.done_noeof:
    call pad_zero
    mov rax, rcx
    ret


pad_zero:
    push rcx
.ploop:
    cmp rcx, 32
    jge .pdone
    mov byte [rdx + rcx], 0
    inc rcx
    jmp .ploop
.pdone:
    pop rcx
    ret


hex_encode:
    push rbx
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    jge .done
    mov bl, [rdi + rcx]

    mov al, bl
    shr al, 4
    movzx rax, al
    mov al, [hex_digits_lo + rax]
    mov [rsi + rcx*2], al

    mov al, bl
    and al, 0x0F
    movzx rax, al
    mov al, [hex_digits_lo + rax]
    mov [rsi + rcx*2 + 1], al

    inc rcx
    jmp .loop
.done:
    pop rbx
    ret

; writes name_buf(32) + password_buf(32) + license_buf(32) to db
db_append_account:
    mov rax, 2; open
    lea rdi, [db_path]
    mov rsi, 0x42
    mov rdx, 644o
    syscall
    cmp rax, 0
    jl .fail
    mov r9, rax

    mov rax, 8 ; lseek
    mov rdi, r9
    mov rsi, 0
    mov rdx, 2
    syscall

    mov rax, 1
    mov rdi, r9
    lea rsi, [name_buf]
    mov rdx, 32
    syscall

    mov rax, 1
    mov rdi, r9
    lea rsi, [password_buf]
    mov rdx, 32
    syscall

    mov rax, 1
    mov rdi, r9
    lea rsi, [license_buf]
    mov rdx, 32
    syscall

    mov rax, 3; close
    mov rdi, r9
    syscall
.fail:
    ret


db_find_account:
    mov rax, 2
    lea rdi, [db_path]
    mov rsi, 0
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .not_found
    mov r9, rax

.read_loop:
    mov rax, 0
    mov rdi, r9
    lea rsi, [file_buf]
    mov rdx, 96
    syscall
    cmp rax, 96
    jne .close_not_found

    xor rcx, rcx
.cmp_name:
    cmp rcx, 32
    jge .name_ok
    mov al, [file_buf + rcx]
    cmp al, [name_buf + rcx]
    jne .read_loop
    inc rcx
    jmp .cmp_name
.name_ok:
    xor rcx, rcx
.cmp_pass:
    cmp rcx, 32
    jge .found
    mov al, [file_buf + 32 + rcx]
    cmp al, [password_buf + rcx]
    jne .read_loop
    inc rcx
    jmp .cmp_pass

.found:
    xor rcx, rcx
.copy_license:
    cmp rcx, 32
    jge .close_found
    mov al, [file_buf + 64 + rcx]
    mov [session_license + rcx], al
    inc rcx
    jmp .copy_license
.close_found:
    mov rax, 3
    mov rdi, r9
    syscall
    mov rax, 1
    ret

.close_not_found:
    mov rax, 3
    mov rdi, r9
    syscall
.not_found:
    mov rax, 0
    ret

close_client:
    mov rax, 3
    mov rdi, r13
    syscall

    mov rax, 60
    mov rdi, 0
    syscall

fail:
    neg rax
    mov rdi, rax
    mov rax, 60
    syscall

section .data
    reuse_val: dd 1
