eval "$(fnm env --use-on-cd --shell bash)"
bind 'set bell-style none'  # causes flickering

# use msys2 telnet since windows one doesn't like OpenVMS
alias telnet='/c/msys64/usr/bin/telnet.exe'

# load functions
if [[ $- == *i* ]]; then
  [ -r "$HOME/.bash_functions" ] && source "$HOME/.bash_functions"
fi

# custom prompt
PS1='\[\033]0;$PWD\007\]'      # set window title
PS1="$PS1"'\n'                 # new line
PS1="$PS1"'\[\033[32m\]'       # change to green
PS1="$PS1"'mike '              # changed to my name, was: user@host<space>
PS1="$PS1"'\[\033[35m\]'       # change to purple
PS1="$PS1"'\s '                # changed to active shell, was: show MSYSTEM
PS1="$PS1"'\[\033[33m\]'       # change to brownish yellow
PS1="$PS1"'\w'                 # current working directory
PS1="$PS1"'\[\033[0m\]'        # change color
PS1="$PS1"'\n'                 # new line
PS1="$PS1"'$ '                 # prompt: always $