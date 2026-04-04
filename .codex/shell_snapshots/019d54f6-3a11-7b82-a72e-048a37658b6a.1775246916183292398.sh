# Snapshot file
# Unset all aliases to avoid conflicts with functions
# Functions
__systemd_osc_context_common () 
{ 
    if [ -f /etc/machine-id ]; then
        printf ";machineid=%.36s" "$(< /etc/machine-id)";
    fi;
    printf ";user=%.255s;hostname=%.255s;bootid=%.36s;pid=%.20d" "$USER" "$HOSTNAME" "$(< /proc/sys/kernel/random/boot_id)" "$$"
}
__systemd_osc_context_escape () 
{ 
    echo "$1" | sed -e 's/\\/\\x5c/g' -e 's/;/\\x3b/g' -e 's/[[:cntrl:]]/⍰/g'
}
__systemd_osc_context_precmdline () 
{ 
    local systemd_exitstatus="$?" systemd_signal;
    if [ -n "${systemd_osc_context_cmd_id:-}" ]; then
        if [ "$systemd_exitstatus" -gt 128 ] && systemd_signal=$(kill -l "$systemd_exitstatus" 2>&-); then
            printf "\033]3008;end=%.64s;exit=failure;status=%d;signal=SIG%s\033\\" "$systemd_osc_context_cmd_id" "$systemd_exitstatus" "$systemd_signal";
        else
            if [ "$systemd_exitstatus" -ne 0 ]; then
                printf "\033]3008;end=%.64s;exit=failure;status=%d\033\\" "$systemd_osc_context_cmd_id" $((systemd_exitstatus));
            else
                printf "\033]3008;end=%.64s;exit=success\033\\" "$systemd_osc_context_cmd_id";
            fi;
        fi;
    fi;
    if [ -z "${systemd_osc_context_shell_id:-}" ]; then
        read -r systemd_osc_context_shell_id < /proc/sys/kernel/random/uuid;
    fi;
    printf "\033]3008;start=%.64s%s;type=shell;cwd=%.255s\033\\" "$systemd_osc_context_shell_id" "$(__systemd_osc_context_common)" "$(__systemd_osc_context_escape "$PWD")";
    read -r systemd_osc_context_cmd_id < /proc/sys/kernel/random/uuid
}
__systemd_osc_context_ps0 () 
{ 
    [ -n "${systemd_osc_context_cmd_id:-}" ] || return;
    printf "\033]3008;start=%.64s%s;type=command;cwd=%.255s\033\\" "$systemd_osc_context_cmd_id" "$(__systemd_osc_context_common)" "$(__systemd_osc_context_escape "$PWD")"
}
_fvm_completion () 
{ 
    local words cword;
    if type _get_comp_words_by_ref &> /dev/null; then
        _get_comp_words_by_ref -n = -n @ -n : -w words -i cword;
    else
        cword="$COMP_CWORD";
        words=("${COMP_WORDS[@]}");
    fi;
    local si="$IFS";
    IFS='
' COMPREPLY=($(COMP_CWORD="$cword" COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" fvm completion -- "${words[@]}" 2> /dev/null)) || return $?;
    IFS="$si";
    if type __ltrim_colon_completions &> /dev/null; then
        __ltrim_colon_completions "${words[cword]}";
    fi
}
gawklibpath_append () 
{ 
    [ -z "$AWKLIBPATH" ] && AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`;
    export AWKLIBPATH="$AWKLIBPATH:$*"
}
gawklibpath_default () 
{ 
    unset AWKLIBPATH;
    export AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`
}
gawklibpath_prepend () 
{ 
    [ -z "$AWKLIBPATH" ] && AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`;
    export AWKLIBPATH="$*:$AWKLIBPATH"
}
gawkpath_append () 
{ 
    [ -z "$AWKPATH" ] && AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`;
    export AWKPATH="$AWKPATH:$*"
}
gawkpath_default () 
{ 
    unset AWKPATH;
    export AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`
}
gawkpath_prepend () 
{ 
    [ -z "$AWKPATH" ] && AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`;
    export AWKPATH="$*:$AWKPATH"
}

# setopts 3
set -o braceexpand
set -o hashall
set -o interactive-comments

# aliases 0

# exports 88
declare -x ASDF_DIR="/home/linuxbrew/.linuxbrew/opt/asdf/libexec"
declare -x BUN_INSTALL="/home/wkochanowski/.bun"
declare -x CODEX_HOME="/home/wkochanowski/code/family-todo/.codex"
declare -x CODEX_MANAGED_BY_NPM="1"
declare -x COLORTERM="truecolor"
declare -x DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
declare -x DEBUGINFOD_URLS="https://debuginfod.archlinux.org "
declare -x DESKTOP_SESSION="plasma"
declare -x DISPLAY=":1"
declare -x GHOSTTY_BIN_DIR="/usr/bin"
declare -x GHOSTTY_RESOURCES_DIR="/usr/share/ghostty"
declare -x GHOSTTY_SHELL_FEATURES="cursor:blink,path,title"
declare -x GTK2_RC_FILES="/etc/gtk-2.0/gtkrc:/home/wkochanowski/.gtkrc-2.0:/home/wkochanowski/.config/gtkrc-2.0"
declare -x GTK_RC_FILES="/etc/gtk/gtkrc:/home/wkochanowski/.gtkrc:/home/wkochanowski/.config/gtkrc"
declare -x HOME="/home/wkochanowski"
declare -x HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
declare -x HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
declare -x HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
declare -x ICEAUTHORITY="/run/user/1000/iceauth_CAQzWS"
declare -x INFOPATH="/home/linuxbrew/.linuxbrew/share/info:"
declare -x KDE_APPLICATIONS_AS_SCOPE="1"
declare -x KDE_FULL_SESSION="true"
declare -x KDE_SESSION_UID="1000"
declare -x KDE_SESSION_VERSION="6"
declare -x LANG="pl_PL.UTF-8"
declare -x LANGUAGE=""
declare -x LC_ADDRESS="pl_PL.UTF-8"
declare -x LC_IDENTIFICATION="pl_PL.UTF-8"
declare -x LC_MEASUREMENT="pl_PL.UTF-8"
declare -x LC_MONETARY="pl_PL.UTF-8"
declare -x LC_NAME="pl_PL.UTF-8"
declare -x LC_NUMERIC="pl_PL.UTF-8"
declare -x LC_PAPER="pl_PL.UTF-8"
declare -x LC_TELEPHONE="pl_PL.UTF-8"
declare -x LC_TIME="pl_PL.UTF-8"
declare -x LOGNAME="wkochanowski"
declare -x LS_COLORS="rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=00:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.7z=01;31:*.ace=01;31:*.alz=01;31:*.apk=01;31:*.arc=01;31:*.arj=01;31:*.bz=01;31:*.bz2=01;31:*.cab=01;31:*.cpio=01;31:*.crate=01;31:*.deb=01;31:*.drpm=01;31:*.dwm=01;31:*.dz=01;31:*.ear=01;31:*.egg=01;31:*.esd=01;31:*.gz=01;31:*.jar=01;31:*.lha=01;31:*.lrz=01;31:*.lz=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.lzo=01;31:*.pyz=01;31:*.rar=01;31:*.rpm=01;31:*.rz=01;31:*.sar=01;31:*.swm=01;31:*.t7z=01;31:*.tar=01;31:*.taz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tgz=01;31:*.tlz=01;31:*.txz=01;31:*.tz=01;31:*.tzo=01;31:*.tzst=01;31:*.udeb=01;31:*.war=01;31:*.whl=01;31:*.wim=01;31:*.xz=01;31:*.z=01;31:*.zip=01;31:*.zoo=01;31:*.zst=01;31:*.avif=01;35:*.jpg=01;35:*.jpeg=01;35:*.jxl=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.webp=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:*~=00;90:*#=00;90:*.bak=00;90:*.crdownload=00;90:*.dpkg-dist=00;90:*.dpkg-new=00;90:*.dpkg-old=00;90:*.dpkg-tmp=00;90:*.old=00;90:*.orig=00;90:*.part=00;90:*.rej=00;90:*.rpmnew=00;90:*.rpmorig=00;90:*.rpmsave=00;90:*.swp=00;90:*.tmp=00;90:*.ucf-dist=00;90:*.ucf-new=00;90:*.ucf-old=00;90:"
declare -x MAIL="/var/spool/mail/wkochanowski"
declare -x MANAGERPID="1043"
declare -x MANAGERPIDFDID="1343"
declare -x MEMORY_PRESSURE_WATCH="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-com.mitchellh.ghostty.service/memory.pressure"
declare -x MEMORY_PRESSURE_WRITE="c29tZSAyMDAwMDAgMjAwMDAwMAA="
declare -x MOTD_SHOWN="pam"
declare -x NVM_BIN="/home/wkochanowski/.nvm/versions/node/v22.14.0/bin"
declare -x NVM_CD_FLAGS=""
declare -x NVM_DIR="/home/wkochanowski/.nvm"
declare -x NVM_INC="/home/wkochanowski/.nvm/versions/node/v22.14.0/include/node"
declare -x OMX_SESSION_ID="omx-1775244093933-oasnp1"
declare -x OMX_TEAM_WORKER_LAUNCH_ARGS="--dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort=\"high\""
declare -x PAM_KWALLET5_LOGIN="/run/user/1000/kwallet5.socket"
declare -x PATH="/home/wkochanowski/.bun/bin:/home/wkochanowski/.bun/bin:/home/wkochanowski/code/family-todo/.codex/tmp/arg0/codex-arg0c5MThV:/home/linuxbrew/.linuxbrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/path:/home/wkochanowski/.bun/bin:/home/wkochanowski/.bun/bin:/home/wkochanowski/.local/bin:/home/wkochanowski/bin:/home/wkochanowski/.local/share/gem/ruby/3.4.0/bin:/home/wkochanowski/.asdf/shims:/home/linuxbrew/.linuxbrew/opt/asdf/libexec/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/home/wkochanowski/.nvm/versions/node/v22.14.0/bin:/home/wkochanowski/.krew/bin:/home/wkochanowski/bin:/home/wkochanowski/go/bin:/home/wkochanowski/.bin:/home/wkochanowski/.Pokemon-Terminal:/home/wkochanowski/.bun/bin:/home/wkochanowski/.bun/bin:/home/wkochanowski/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/wkochanowski/.spicetify:/home/wkochanowski/.bash-my-aws/bin:/home/wkochanowski/.pulumi/bin:/home/wkochanowski/.local/bin:/home/wkochanowski/.spicetify:/home/wkochanowski/.spicetify:/home/wkochanowski/.spicetify"
declare -x QT_LINUX_ACCESSIBILITY_ALWAYS_ON="1"
declare -x QT_WAYLAND_RECONNECT="1"
declare -x SESSION_MANAGER="local/b250:@/tmp/.ICE-unix/1257,unix/b250:/tmp/.ICE-unix/1257"
declare -x SHELL="/usr/bin/bash"
declare -x SHLVL="3"
declare -x SSH_AGENT_PID="5323"
declare -x SSH_AUTH_SOCK="/home/wkochanowski/.ssh/agent/s.sXCRZOPFYY.agent.pmqrIkRIgs"
declare -x STARSHIP_SESSION_KEY="1981496841469018"
declare -x STARSHIP_SHELL="bash"
declare -x SYSTEMD_EXEC_PID="5235"
declare -x TERM="screen-256color"
declare -x TERMINFO="/usr/share/terminfo"
declare -x TERM_PROGRAM="tmux"
declare -x TERM_PROGRAM_VERSION="3.6a"
declare -x TF_FORCE_LOCAL_BACKEND="1"
declare -x TMUX="/tmp/tmux-1000/default,300662,0"
declare -x TMUX_PANE="%0"
declare -x TMUX_PLUGIN_MANAGER_PATH="/home/wkochanowski/.tmux/plugins/"
declare -x USER="wkochanowski"
declare -x VISUAL="vim"
declare -x WAYLAND_DISPLAY="wayland-0"
declare -x XAUTHORITY="/run/user/1000/xauth_LGLLjg"
declare -x XDG_CONFIG_DIRS="/home/wkochanowski/.config/kdedefaults:/etc/xdg:/usr/share/manjaro-kde-settings/xdg:/usr/share/manjaro-kde-settings/xdg:/usr/share/manjaro-kde-settings/xdg:/usr/share/manjaro-kde-settings/xdg"
declare -x XDG_CURRENT_DESKTOP="KDE"
declare -x XDG_DATA_DIRS="/home/wkochanowski/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/home/wkochanowski/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
declare -x XDG_MENU_PREFIX="plasma-"
declare -x XDG_RUNTIME_DIR="/run/user/1000"
declare -x XDG_SEAT="seat0"
declare -x XDG_SEAT_PATH="/org/freedesktop/DisplayManager/Seat0"
declare -x XDG_SESSION_CLASS="user"
declare -x XDG_SESSION_DESKTOP="KDE"
declare -x XDG_SESSION_ID="2"
declare -x XDG_SESSION_PATH="/org/freedesktop/DisplayManager/Session1"
declare -x XDG_SESSION_TYPE="wayland"
declare -x XDG_VTNR="1"
declare -x XKB_DEFAULT_LAYOUT="pl"
declare -x _JAVA_AWT_WM_NONREPARENTING="1"
