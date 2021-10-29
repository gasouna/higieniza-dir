#!/bin/bash

# Funções
log(){
    if [ -f $1 ]
    then
        echo $2 >> $1
    else
        echo $2 > $1
    fi
}

higieniza(){
    #Parâmetros:
    #  1 - Nome do diretório
    #  2 - Arquivo de log
    #  3 - IP interno do Garagem correspondente (exemplo 10.14.0.46)
    #  4 - Registro resultante do ls -l dentro do workspace (owner|grupo|data_criacao|nome_diretorio)
    #  5 - Arquivo onde ficam os dados referentes a execução
    #  6 - Indicador de status: fora_grupo (usuário que passará pela higienização por não estar em nenhum dos grupos) ou numério (usuário que não foi encontrado)
    #  7 - Tolerância (em dias) para o bloqueio dos arquivos

    if [ `find /opt/apl/workspace/$1 -type f | wc -l` - eq 0 ]
    then
        log $2 "[$3][`date "+%Y-%m-%d %H:%M"`] Diretório $1 vazio. Excluindo..."
        echo "$3|$4|`du -d0 /opt/apl/workspace/$1 | awk {'print $1'}`|$6|E" >> $5
        rm -rf /opt/apl/workspace/$1 2>> $2
    else
        if [ `find /opt/apl/workspace/$1 -type f -atime -$7 | wc -l` -gt 1 ]
        then
            log $2 "[$3][`date "+%Y-%m-%d %H:%M"`] Diretório $1 possui arquivos recentes. Mantendo até a próxima execução."
            echo "$3|$4|`du -d0 /opt/apl/workspace/$1 | awk {'print $1'}`|$6|N" >> $5
        else
            log $2 "[$3][`date "+%Y-%m-%d %H:%M"`] Diretório $1 não está vazio. Movendo..."
            echo "$3|$4|`du -d0 /opt/apl/workspace/$1 | awk {'print $1'}`|$6|M" >> $5
            data_hig=`date "+%Y%m%d"`
            if [ -d /workspace/para_excluir_hot-${data_hig} ]
            then
                mv /opt/apl/workspace/$1 /workspace/para_excluir_hot-${data_hig}
                chown root:root /workspace/para_excluir_hot-${data_hig}/$1
                chmod 770 /workspace/para_excluir_hot-${data_hig}/$1
            else
                mkdir -p /workspace/para_excluir_hot-${data_hig}
                mv /opt/apl/workspace/$1 /workspace/para_excluir_hot-${data_hig}
                chown root:root /workspace/para_excluir_hot-${data_hig}/$1
                chmod 770 /workspace/para_excluir_hot-${data_hig}/$1
            fi
        fi
    fi
}
#############

### Definições inicias
###############################
data_execucao=`date "+%Y-%m-%d"`
garagem=`hostname -I | sed s'/ //g'`

DIR_HIGIENIZACAO=/workspace/Monitoramento/Higienizacao_hot
ARQ_LOG_HIG=${DIR_HIGIENIZACAO}/log_execucao_${garagem}_${data_execucao}.log
DADOS_EXEC=${DIR_HIGIENIZACAO}/base_higienizacao_hot_${garagem}_${data_execucao}.out
ARQ_USUARIOS=/workspace/Monitoramento/usuarios_${garagem}.conf
###############################

log $ARQ_LOG_HIG "###################################################################################"
log $ARQ_LOG_HIG "#                         HIGIENIZAÇÃO DO DIRETÓRIO HOT                           #"
log $ARQ_LOG_HIG "###################################################################################"

### Higienização do diretório hot
###############################
log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Criação da lista de diretórios dentro do /opt/apl/workspace."
ls -l --time-style="+%Y-%m-%d@%H:%M" /opt/apl/workspace | awk '{print $3,$4,$6,$7}' | sed s'/ //g' | sed s'/@/ /g' > ${DIR_HIGIENIZACAO}/lista_diretorios_hot_${garagem}_${data_execucao}.out
sed -i 1d ${DIR_HIGIENIZACAO}/lista_diretorios_hot_${garagem}_${data_execucao}.out
if [ -s ${DIR_HIGIENIZACAO}/lista_diretorios_hot_${garagem}_${data_execucao}.out ]
then
    log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Iniciando a higienização dos diretórios."
    cat ${DIR_HIGIENIZACAO}/lista_diretorios_hot_${garagem}_${data_execucao}.out | while read registro
    do
        usr=`echo $registro | cut -d"|" -f4`
        if [ $usr == "root" ]
        then
            :
        elif [ `echo $usr | cut -d"-" -f1` == "para_excluir_hot" ]
        then
            data_dir=`echo $usr | cut -d"-" -f2`
            data_dir_s=`$(date -d "$data_dir" +%s)`
            data_execucao_s=`$(date -d "$data_execucao" +%s)`
            dias=$(( (data_execucao_s - data_dir_s) / 86400 ))
            if [ $dias -gt 15 ]
            then
                log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Removendo $usr"
                rm -rf /opt/apl/workspace/$usr
            fi
        else
            id -u $usr >> /dev/null 2>> /dev/null
            if [ $? -ne 0 ]
            then
                log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Usuário $usr não encontrado."
                higieniza $usr $ARQ_LOG_HIG "${garagem}" "${registro}" $DADOS_EXEC "numerico" 10
            else
                if [ -s $ARQ_USUARIOS ]
                then
                    grep $usr $ARQ_USUARIOS >> /dev/null
                    if [ $? -eq 0 ]
                    then
                        log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Usuário $usr tem acesso aos grupos. Nada a fazer."
                    else
                        higieniza $usr $ARQ_LOG_HIG "${garagem}" "${registro}" $DADOS_EXEC "fora_grupo" 15
                    fi
                fi
            fi
        fi
    done
else
    log $ARQ_LOG_HIG "[$garagem][`date "+%Y-%m-%d %H:%M"`] Lista de diretórios não encontrada."
fi