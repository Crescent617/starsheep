# 1. 记录命令开始时间
_starsheep_preexec() {
    # 使用精度更高的 EPOCHREALTIME (秒.微秒)
    STARSHEEP_START_TIME=$EPOCHREALTIME
}

# 2. 计算时长并清理
_starsheep_precmd() {
    # 立即保存退出码，防止被后续命令覆盖
    local last_status=$?
    
    local duration=0
    if [[ -n $STARSHEEP_START_TIME ]]; then
        local now=$EPOCHREALTIME
        # 计算毫秒: (now - start) * 1000
        # zsh 的算术运算支持浮点数
        duration=$(( (now - STARSHEEP_START_TIME) * 1000 ))
        unset STARSHEEP_START_TIME
    fi

    # 获取后台任务数量
    local job_count=$(jobs | wc -l | tr -d ' ')

    # 将所有计算好的状态存入环境变量或直接在 prompt 调用时传递
    # 这里通过参数传递给 promptMain 处理
    STARSHEEP_LAST_STATUS=$last_status
    STARSHEEP_LAST_DURATION=$duration
    STARSHEEP_JOBS=$job_count
}

# 3. 渲染 Prompt
_starsheep_get_prompt() {
    starsheep prompt \
        --shell zsh \
        --last-exit-code "$STARSHEEP_LAST_STATUS" \
        --last-duration-ms "$STARSHEEP_LAST_DURATION" \
        --jobs "$STARSHEEP_JOBS"
}

# 注册钩子
typeset -ag precmd_functions
if [[ ${precmd_functions[(ie)_starsheep_precmd]} -gt ${#precmd_functions} ]]; then
    precmd_functions+=(_starsheep_precmd)
fi

typeset -ag preexec_functions
if [[ ${preexec_functions[(ie)_starsheep_preexec]} -gt ${#preexec_functions} ]]; then
    preexec_functions+=(_starsheep_preexec)
fi

# 开启变量替换并设置 PROMPT
setopt PROMPT_SUBST
PROMPT='$(_starsheep_get_prompt)'
