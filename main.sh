#!/bin/bash

#实际使用对以下全局变量做出修改以符合实际应用场景，且需要把第104行for循环的层数设为release目录下bin这一层前面的"/"的个数
#全局变量
TODAY=20180522     #TODAY=`date +'%Y%m%d'`
releaseDir="/home/uat_yssett_zn/release_tmp/"  #本地下载存放目录
UMCDir=/home/uat_yssett_zn/UMC_tmp/         #本地要替换的主目录
fileToDownload="yssfgs_${TODAY}.tar.gz"    #要下载的文件名
SOURCE_DB="uat_yssett_zn/yssett_50zn@172.30.252.103:1521/yssett"   #数据库连接信息
remoteDownloadDir="/oradcdata/yssett_x_tmp/release-cannotdelete/"${TODAY}"/fgs"   #远程下载目录
remoteIP="144.131.254.120"       #远程下载服务器的IP地址
remoteUser="mak_yssett_x"   #下载服务器的用户名
remotePass="yssett_311"     #下载服务器的用户密码

if [ ! -d $releaseDir/replaceTmp ];then       #检查临时文件夹是否存在
	mkdir $releaseDir/replaceTmp
fi

if [ ! -d $releaseDir/logTmp ];then       #检查日志文件夹是否存在
	mkdir $releaseDir/logTmp
fi

#-----------------------------------下载部分---------------------------------------
#下载文件，三个参数，一个是远程下载目录，一个是本地保存目录，一个是下载文件名
down()   
{	cd $2
	ftp -n <<!
			open ${remoteIP}
			user ${remoteUser} ${remotePass}
			cd $1
			binary
			get $3
			bye
!

}
#下载某个文件，找不到就等待5分钟再下
download()    #三个参数，分别代表远程下载目录，本地存放目录，下载文件名
{
	down $1 $2 $3
	while true
	do
		if [ ! -f $3 ]
		then
			echo "没有要替换的文件，需要等待" |tee -a $releaseDir/logTmp/log_$TODAY
			sleep 300s
			down $1 $2 $3
		else
			echo "存在要替换的文件，文件下载成功" |tee -a $releaseDir/logTmp/log_$TODAY
			break
		fi
	done
}
#----------------------------------------------------------------------------------

#-----------------------------------替换文件部分-----------------------------------

#releseUMC目录下相对应的代码进行MD5码比较，如果不同，则替换UMC目录下相应代码
##将脚本应用到不同服务器时，把第104行for循环的层数设为release目录下bin这一层前面的"/"的个数

exchangeFIle() {
		#以文件2替换文件1

        mv $1 $1_bak$TODAY
        cp $2 $1
        chmod 777 $1  
}
#文件MD5比对
checkFIle() {

        echo `basename $1` |tee -a $releaseDir/logTmp/log_$TODAY
        f1=`md5sum $1|cut -d ' ' -f1`
        echo "$f1" |tee -a $releaseDir/logTmp/log_$TODAY

        f2=`md5sum $2|cut -d ' ' -f1`
        echo "$f2" |tee -a $releaseDir/logTmp/log_$TODAY
        
        if [ "$f1" = "$f2" ];then
                echo "文件$1没有变化！请检查！" |tee -a $releaseDir/logTmp/log_$TODAY
                echo |tee -a $releaseDir/logTmp/log_$TODAY
                return -1
        else
                return 1
        fi
}


exchangeDir()
{
	#替换之前备份要被替换的文件列表
	find $releaseDir$TODAY/ -type f > $releaseDir/replaceTmp/filelist.tmp
    while read line
    do
        if [[ $line =~ bin ||  $line =~ lib || $line =~ etc || $line =~ prc || $line =~ sbin || $line =~ sql ]];then
			
			filepathcut=`echo ${line} | sed -r 's/([0-9]{4})(0[1-9]|1[012])(0[1-9]|[1-2][0-9]|3[01])//' | awk -F'//' '{print $2}'`
            releaseFile=${releaseDir}${TODAY}"/"${filepathcut}
            UMCFile=${UMCDir}${filepathcut}
			
			#新增代码判断
			if [ ! -f ${UMCFile} ]
			then
				echo "有新增代码，请注意" |tee -a $releaseDir/logTmp/log_$TODAY
				cp ${releaseFile} ${UMCFile} && echo "新增代码文件${UMCFile}成功"
			else
				checkFIle $UMCFile $releaseFile
				if [ $? -eq 1 ];then
					echo "MD5码比对OK，开始替换代码" |tee -a $releaseDir/logTmp/log_$TODAY
					exchangeFIle $UMCFile $releaseFile
					echo "${UMCFile}代码替换完成！" |tee -a $releaseDir/logTmp/log_$TODAY
					echo |tee -a $releaseDir/logTmp/log_$TODAY
				fi
			fi
        fi

    done < $releaseDir/replaceTmp/filelist.tmp
	echo "所有文件替换完成" |tee -a $releaseDir/logTmp/log_$TODAY
}

#----------------------------------------------------------------------------------

#-----------------------------------回退部分---------------------------------------

#回滚文件，一个参数是文件路径
roll_back_all() 
{
    fileBakname=`basename $1`
	#去除文件名下划线后面的部分
    fileBasename=${fileBakname%_*}
    filePath=`dirname $1` 
	echo "回退"$filePath/$fileBasename"文件" |tee -a $releaseDir/logTmp/log_$TODAY
    mv $filePath/$fileBasename $filePath/${fileBasename}"_rollback" #将之前替换的文件改名成后面加"_rollback"
    mv $1 $filePath/$fileBasename   #将有"_bak$TODAY"后缀的文件改名成去点后缀
}
#----------------------------------------------------------------------------------
#---------------------------远程登陆并判断是否存在sql文件夹------------------------
#判断远程服务器sql文件是否存在
loginAndTest()   #三个参数分别是：ip user password 
{
	expect -c "
	spawn ssh $2@$1 test -d ${remoteDownloadDir}/sql||echo xxxxxxxxxxxxxooooooooooo
	expect yes* {send yes\n;expect Password:;send $PD\r} Password:
	send ${3}\r
	expect xxxxxxxxxxxxxooooooooooo { exit 55 } 
"
	if [ $? -eq 55 ];then
        echo "没有要执行的sql文件"
		return 1
	else
		echo "存在要执行的sql文件,需要远程登陆打包下载"
        return 0
	fi
}
#--------------------------------------------------------------------------------
#--------------远程登录到服务器，并将一个文件夹打包------------------------------
# send 后面直接接命令变量会出错
# 四个参数分别是：ip user password filename
loginAndTar()
{
	#echo ${@:4}
	expect -c "                
            set timeout -1
            spawn ssh -p 22 ${2}@${1}
            expect yes* {send yes\n;expect Password:;send $PD\r} Password:
			send $3\r
			expect \> 
			send \"cd ${remoteDownloadDir}\r\"
			send \"tar -zxvf ${fileToDownload}\r\";\
			send \"tar -zcvf full_${TODAY}.tar.gz ${TODAY} ${4}\r\";\
			send exit\r
			set timeout 60
			expect eof"
}

#-----------------------------------SQL解析部分------------------------------------
manageSqlFile()       #两个参数：一个要替换的时间，一个是sql文件路径
{
	# 建立存放存储过程代码的目录
	if [ ! -d ${2}"tmp/" ];then  
		mkdir ${2}"tmp/"
	fi
	#循环处理今日的sql文件
	find $2 -name *.sql > $releaseDir/replaceTmp/sqlfilelist.tmp
	while read line
	do
		file=${line}
		filebasename=`basename $file`
		#将sql文件中BAT_DAT日期值全部设置成当天时间
		echo "检查并替换${file}文件中的BAT_DATE值" |tee -a $releaseDir/logTmp/log_$TODAY
		grep -A1 'BAT_DATE' -rl ${file}
		if [ $? -ne 0 ];then
			echo ${file}"中没有BAT_DATE字段，无需替换"|tee -a $releaseDir/logTmp/log_$TODAY
		else
			#直接将sql文件中的BAT_DATE值替换成参数
			# sed -i -r "s/'([0-9]{4})(0[1-9]|1[012])(0[1-9]|[1-2][0-9]|3[01])'/'${1}'/" `grep -A1 'BAT_DATE' -rl ${file}`
			#将sql文件中的BAT_DATE值取出来，然后用参数将其替换，最后判断是否为空
			fl=`grep -A1 'BAT_DATE' ${file} |sed -r "s/'([0-9]{4})(0[1-9]|1[012])(0[1-9]|[1-2][0-9]|3[01])'/aa\1\2\3aa/" | awk -F'aa' '{print $2}'| sed -r "s/20180726//g"`
			if [ -z ${fl} ]
			then
				echo "${file}文件中BAT_DATE没有错误" |tee -a $releaseDir/logTmp/log_$TODAY
			else
				echo "${file}文件中BAT_DATE有错误，请检查！" |tee -a $releaseDir/logTmp/log_$TODAY
				exit 1
			fi
		fi
		#往sql文件中添加语句生成存储过程
		echo 'create or replace procedure myproc
(
	fl out varchar2
)
is 
	errorCode number; --异常编码
	errorMsg varchar2(1000); --异常信息
	errorLine varchar2(1000); --异常行号
Begin' >${2}"tmp/"${filebasename}
		cat ${file} >> ${2}"tmp/"${filebasename}
			
		echo "
COMMIT;
fl :='ExecuteSuccess';
DBMS_OUTPUT.PUT_LINE('提交成功');
EXCEPTION
       WHEN OTHERS THEN
			errorCode := SQLCODE;
			errorMsg := SUBSTR(SQLERRM, 1, 200); 
			errorLine := dbms_utility.format_error_backtrace();
			fl :='failure,errorCode=' || errorCode || ',errorMsg=' || errorMsg || ',errorLine=' || errorLine;
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('回滚成功' || fl || SQLCODE || SUBSTR(SQLERRM, 1, 200));
END;
/" >> ${2}"tmp/"${filebasename}
		#执行sql文件
		echo "开始执行${file}代码" |tee -a $releaseDir/logTmp/log_$TODAY
		
		#连接数据库执行sql文件
		sqlfile=`echo ${2}"tmp/"${filebasename}`
		# iconv -f UTF-8 -t GB18030 ${sqlfile} > ${sqlfile}.GB2312
		# sqlfile_GB2312=`echo ${sqlfile}.GB2312`
		tmp=`sqlplus -s ${SOURCE_DB} >${releaseDir}logTmp/${filebasename}_log_${TODAY}_sql 2>&1<<EOF
		set heading off feedback off pagesize 0 verify off echo on numwidth 4 linesize 1000;
		--执行脚本文件生成存储过程
		@${sqlfile}
		--定义临时表
		create table aatmp(
			fl varchar2(1000) not null
		)
		/
		--执行存储过程并将返回值插入临时表
		declare fl varchar2(1000);
		begin
			myproc(fl);
			insert into aatmp values(fl);
		end;
		/
		--查询返回值
		select * from aatmp;
		--删掉临时表和存储过程
		drop table aatmp;
		drop procedure myproc;
		quit;
EOF`
		iconv -f GB2312 -t UTF-8 ${releaseDir}logTmp/${filebasename}_log_${TODAY}_sql > ${releaseDir}logTmp/${filebasename}_log_${TODAY}
		rm -f ${releaseDir}logTmp/${filebasename}_log_${TODAY}_sql
		flag=`grep -o 'ExecuteSuccess' ${releaseDir}logTmp/${filebasename}_log_${TODAY}`
		if [ -z ${flag} ];then 
			echo "执行${file}文件中的sql语句失败"|tee -a $releaseDir/logTmp/log_${TODAY}
			echo "错误信息为：" |tee -a $releaseDir/logTmp/log_${TODAY}
			grep -E 'ORA|PL|SP' ${releaseDir}logTmp/${filebasename}_log_${TODAY} |tee -a $releaseDir/logTmp/log_${TODAY}
			echo "详细错误信息，请查看日志文件${releaseDir}logTmp/${filebasename}_log_${TODAY}" |tee -a $releaseDir/logTmp/log_${TODAY}
			echo |tee -a $releaseDir/logTmp/log_$TODAY
		else
			echo "执行${file}中sql语句成功"|tee -a $releaseDir/logTmp/log_${TODAY}
			echo |tee -a $releaseDir/logTmp/log_$TODAY
		fi

		
	done < $releaseDir/replaceTmp/sqlfilelist.tmp
	
	rm -rf ${2}"tmp/"
	#echo "sql事务代码运行完成，请查看sql日志文件${releaseDir}logTmp/*_log_${TODAY}_sql 看是否执行成功" |tee -a $releaseDir/logTmp/log_$TODAY
}
#------------------------------------上传文件-------------------------------------
Upload()
{
	ftp -n &>tmp_${TODAY}.txt<<!
	open $1
	user $2 $3
	cd release
	binary
	put lib_bin_20180816.tar.gz
	bye
!
}
#------------------------循环将文件复制到各个服务器------------------------
scp()
{
	#需要有一个文件serverInfo.txt存储其他服务器的IP地址、用户名和密码
	#cat serverInfo.txt
	echo "开始复制文件到其他服务器" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
	while read line
	do
		ip=`echo $line |awk -F, '{print $1}'`
		user=`echo $line |awk -F, '{print $2}'`
		pass=`echo $line |awk -F, '{print $3}'`
		echo "${user}"
		Upload ${ip} ${user} ${pass}
		tmp=`cat tmp_${TODAY}.txt`
		if [ -z ${tmp} ]
		then
			echo "复制文件到${ip}服务器成功" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
		else
			echo "复制文件到${ip}服务器失败" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
			exit 1
		fi
	done < serverInfo.txt
	rm -f tmp_${TODAY}.txt
	echo "复制文件到其他服务器完成" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
}
#---------------------------------远程登陆服务器替换文件--------------------
loginAndExchange()
{
	cat serverInfo.txt | while read line
	do
		ip=`echo $line |awk -F, '{print $1}'`
		user=`echo $line |awk -F, '{print $2}'`
		pass=`echo $line |awk -F, '{print $3}'`
		expect -c "
			log_file expect.log
		    set timeout -1
            spawn ssh -p 22 ${user}@${ip}
            expect yes* {send yes\n;expect Password:;send $PD\r} Password:
			send ${pass}\r
			expect \> 
			send \"cd UMC\r\"
			send \"cp bin bin_bak${TODAY}\r\"
			send \"cp lib lib_bak${TODAY}\r\"
			send \"cd ../release\r\"
			# send \"tar -zxvf lib+bin_${TODAY}.tar.gz -C ../UMC\r\";\
			send \"chmod 777 -R ../UMC/lib\r\"
			send \"chmod 777 -R ../UMC/bin\r\"
			send exit\r
			set timeout 60
			expect eof"
		if [ $? -eq 0 ]
		then
			echo "替换${ip}服务器的文件成功" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
			exit 1
		else
			echo "替换${ip}服务器的文件失败" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
		fi
	done
	echo "替换其他服务器的文件完成" |tee -a $releaseDir/logTmp/${0}_log_$TODAY
}
#-----------------------连接数据库获取其他服务器信息-------------------------------
connDatabase()
{
	sqlplus -s ${SOURCE_DB} >${releaseDir}logTmp/log_${TODAY}_sql.log 2>&1<<EOF
		set heading off feedback off pagesize 0 verify off echo on numwidth 4;
		spool ${UMCDir}serverInfo.txt;
		select ip_addr ||','|| port ||','||user_name||','||user_pswd from Bat_machines_info_rac;
		spool off;
		exit;
EOF
}
#-----------------------------------主函数-----------------------------------------

main()
{
	if [ $# -eq 0 ]
	then
		echo "命令错误，请传参" |tee -a $releaseDir/logTmp/log_$TODAY
		exit 1
	#如果第一个参数为1，则表示替换，第二个参数必须为sql解析中的BAT_DATE日期，第三个参数必须为选择远程下载环境，如果后面再没有参数则表示全部替换，如果还有参数则是指定替换特定文件
	elif [ $1 -eq 1 ]
	then     #第一个参数为1代表替换操作
		#第二个参数为要检查的BAT_DATE
		if [ -z $2 ]
		then
			echo "命令错误，替换必须传参BAT_DATE" |tee -a $releaseDir/logTmp/log_$TODAY
			exit 1
		else
			fla=`echo $2 | sed -r 's/([0-9]{4})(0[1-9]|1[012])(0[1-9]|[1-2][0-9]|3[01])//'`
			if [ ! -z ${fla} ]
			then
				echo "命令错误，传参日期格式不正确"|tee -a $releaseDir/logTmp/log_$TODAY
				exit 1
			fi
		fi
		#第三个参数为选择远程下载环境
		if [ -z $3 ]
		then
			echo "命令错误，替换必须选择远程下载环境"
			exit 1
		elif [ $3 -eq 1 ]     #参数为1时将远程下载环境设置成115环境
		then
			remoteDownloadDir="/oradcdata/yssett_x_tmp/release-cannotdelete/"${TODAY}"/fgs"   #远程下载目录
			remoteIP="144.131.254.120"       #远程下载服务器的IP地址
			remoteUser="mak_yssett_x"   #下载服务器的用户名
			remotePass="yssett_311"     #下载服务器的用户密码
		elif [ $3 -eq 2 ]    #参数为2时将远程下载环境设置成86环境
		then
			remoteDownloadDir="/oradcdata/yssett_x_tmp/release-cannotdelete/"${TODAY}"/fgs"   #远程下载目录
			remoteIP="144.131.254.120"       #远程下载服务器的IP地址
			remoteUser="mak_yssett_x"   #下载服务器的用户名
			remotePass="yssett_311"     #下载服务器的用户密码
		else
			echo "命令错误，第三个参数为选择下载环境，请检查"
			exit 1
		fi
		echo |tee -a $releaseDir/logTmp/log_$TODAY
		exit 1
		#先登陆远程服务器判断是否存在要执行的sql文件
		loginAndTest ${remoteIP} ${remoteUser} ${remotePass}
		if [ $? -eq 0 ]
		then
			#先登陆远程服务器将要执行的sql文件和要替换的文件打包，然后下载
			loginAndTar ${remoteIP} ${remoteUser} ${remotePass} sql && echo "sql文件夹打包成功"|tee -a $releaseDir/logTmp/log_$TODAY
			fileToDownload="full_${TODAY}.tar.gz"
		fi
		#到远程服务器A下载指定文件
		download ${remoteDownloadDir} ${releaseDir} ${fileToDownload}
		echo "开始解压文件"|tee -a $releaseDir/logTmp/log_$TODAY
		tar -zxvf ${fileToDownload} && echo "文件解压成功" |tee -a $releaseDir/logTmp/log_$TODAY
		echo |tee -a $releaseDir/logTmp/log_$TODAY
		if [ -d sql ]
		then
			if [ ! -d SQL ]
			then 
				mkdir SQL
			fi
			if [ ! -d SQL/${TODAY} ]
			then 
				mkdir SQL/${TODAY}
			fi
			mv sql SQL/${TODAY}/
			#遍历解析sql文件
			sqlFilePath=${releaseDir}"SQL/"${TODAY}"/"
			manageSqlFile $2 ${sqlFilePath}
		fi
		if [ -z $3 ]     #没有第三个参数则替换所有文件
		then
			#替换所有文件
			echo "开始替换下载的所有代码" |tee -a $releaseDir/logTmp/log_$TODAY
			exchangeDir
		else           #第三、四。。。个参数则代表要替换的文件名
			#替换指定文件
			echo "开始替换指定代码" |tee -a $releaseDir/logTmp/log_$TODAY
			i=4
			while true
			do 
				if [ -z ${!i} ]; then
					break
				else 
					file_1=`find $UMCDir -name "${!i}"`  #找到UMCDir中要被替换的文件
					file_2=`find $releaseDir${TODAY} -name "${!i}"`  #找到下载文件解压后的替换文件
					if [ -z $file_2 ]; then
						echo "未在下载目录中找到${!i}文件，请检查" |tee -a $releaseDir/logTmp/log_$TODAY
						exit 1
					fi
					if [ -z $file_1 ]; then
						echo "未在本地目录中找到${!i}文件，是新增文件,请注意" |tee -a $releaseDir/logTmp/log_$TODAY
						filepathcut=`echo ${file_2} | sed -r 's/([0-9]{4})(0[1-9]|1[012])(0[1-9]|[1-2][0-9]|3[01])//' | awk -F'//' '{print $2}'`
						UMCFile=${UMCDir}${filepathcut}
						cp ${file_2} ${UMCFile} && echo "新增代码文件${UMCFile}成功"
						break
					fi
					checkFIle $file_1 $file_2

					if [ $? -eq 1 ];then
						echo "MD5码比对OK，开始替换代码" |tee -a $releaseDir/logTmp/log_$TODAY
						exchangeFIle $file_1 $file_2
						echo "${!i}代码替换完成！" |tee -a $releaseDir/logTmp/log_$TODAY
						echo |tee -a $releaseDir/logTmp/log_$TODAY
					fi
					let i++
				fi
			done
		fi
		#代码替换成功后开始打包本地lib和bin文件夹
		# cd UMCDir
		# tar -zcvf lib+bin${TODAY}.tar.gz lib bin
		# connDatabase          #访问数据库将其他服务器信息写入${UMCDir}serverInfo.txt文件中
		# scp				#将文件复制到其他服务器
		# loginAndExchange    #登陆其他服务器备份lib 和 bin,然后利用复制过来的文件替换已有的lib和bin
	elif [ $1 -eq 2 ]    #第一个参数为2代表回退
	then    
		if [ -z "$2" ];then    #如果不存在第二个参数则回退当天替换的所有文件
			find $UMCDir -name "*_bak$TODAY"> $releaseDir/replaceTmp/rollbackfilelist.tmp
			
			while read line
            do
                roll_back_all $line
            done < $releaseDir/replaceTmp/rollbackfilelist.tmp
			echo "当天替换的所有文件回退完成" |tee -a $releaseDir/logTmp/log_$TODAY
			echo |tee -a $releaseDir/logTmp/log_$TODAY
		else				#如果存在两个或以上参数则回退指定参数文件
			i=2
			while true
			do 
				file=`find $UMCDir -name ${!i}_bak$TODAY`
				
				if [ -z "$file" ];then
					echo "没有${!i}文件今天的备份，无法回退，请检查" |tee -a $releaseDir/logTmp/log_$TODAY
					echo |tee -a $releaseDir/logTmp/log_$TODAY
					break
				fi
                roll_back_all ${file}
				echo "${!i}文件回退完成" |tee -a $releaseDir/logTmp/log_$TODAY
				echo |tee -a $releaseDir/logTmp/log_$TODAY
				let i++
				
				if [ -z "${!i}" ]; then
					echo "所有参数文件回退完成" |tee -a $releaseDir/logTmp/log_$TODAY
					echo |tee -a $releaseDir/logTmp/log_$TODAY
					break
				fi
			done
			
		fi			
	else
		echo "命令错误，请检查" |tee -a $releaseDir/logTmp/log_$TODAY
		exit 1
	fi
	
		
}
#---------------------------------------------------------------------------------


#测试sql文件执行
# sqlFilePath=${releaseDir}"SQL/"${TODAY}"/"
# manageSqlFile $1 ${sqlFilePath}


main $1 $2 $3 $4 $5 $6
