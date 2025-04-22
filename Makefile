include .Renviron

.PHONY: upload download snapshot update build

# no sense in uploading the build or the data, when we actually want to build remotely and then download
upload:
	rsync --recursive --verbose --partial --progress --exclude '.*' --exclude 'data/*' --exclude 'docs/*' --exclude 'build/*' --exclude 'renv/*' . ${PISA_BUILD_SERVER}:${PISA_REMOTE_PATH}

# when on wifi, consider that sneakernet is considerably faster
download:
	rsync --recursive --verbose --partial --progress ${PISA_BUILD_SERVER}:${PISA_REMOTE_PATH}/build .

snapshot:
	Rscript -e 'renv::snapshot()'

update: snapshot upload
	ssh ${PISA_BUILD_SERVER} "cd ${PISA_REMOTE_PATH}; Rscript4.4 -e 'renv::restore()'"

build:
	# mkdir build/{2000,2003,2006,2009,2012,2015,2018,2022}/flags
	# mkdir build/{2000,2003,2006,2009,2012,2015,2018,2022}/problems/flags
	ssh ${PISA_BUILD_SERVER} "cd ${PISA_REMOTE_PATH}; Rscript4.4 src/2000/convert.R; Rscript4.4 src/2003/convert.R; Rscript4.4 src/2006/convert.R; Rscript4.4 src/2009/convert.R; Rscript4.4 src/2012/convert.R; Rscript4.4 src/2015/convert.R; Rscript4.4 src/2018/convert.R; Rscript4.4 src/2022/convert.R"

timing:
	ssh ${PISA_BUILD_SERVER} "cd ${PISA_REMOTE_PATH}; Rscript4.4 sandbox/timing.R"

data:
	# 2000
	wget -P data/2000 https://www.oecd.org/pisa/pisaproducts/intcogn_v4.zip
	wget -P data/2000 https://www.oecd.org/pisa/pisaproducts/intscho.zip
	wget -P data/2000 https://www.oecd.org/pisa/pisaproducts/intstud_math.zip
	wget -P data/2000 https://www.oecd.org/pisa/pisaproducts/intstud_read.zip
	wget -P data/2000 https://www.oecd.org/pisa/pisaproducts/intstud_scie.zip

	# 2003
	wget -P data/2003 https://www.oecd.org/pisa/pisaproducts/INT_cogn_2003.zip
	wget -P data/2003 https://www.oecd.org/pisa/pisaproducts/INT_stui_2003_v2.zip
	wget -P data/2003 https://www.oecd.org/pisa/pisaproducts/INT_schi_2003.zip

	# 2006
	wget -P data/2006 https://www.oecd.org/pisa/pisaproducts/INT_Stu06_Dec07.zip
	wget -P data/2006 https://www.oecd.org/pisa/pisaproducts/INT_Sch06_Dec07.zip
	wget -P data/2006 https://www.oecd.org/pisa/pisaproducts/INT_Par06_Dec07.zip
	wget -P data/2006 https://www.oecd.org/pisa/pisaproducts/INT_Cogn06_T_Dec07.zip
	wget -P data/2006 https://www.oecd.org/pisa/pisaproducts/INT_Cogn06_S_Dec07.zip

	# 2009
	wget -P data/2009 https://www.oecd.org/pisa/pisaproducts/INT_STQ09_DEC11.zip
	wget -P data/2009 https://www.oecd.org/pisa/pisaproducts/INT_SCQ09_Dec11.zip
	wget -P data/2009 https://www.oecd.org/pisa/pisaproducts/INT_PAR09_DEC11.zip
	wget -P data/2009 https://www.oecd.org/pisa/pisaproducts/INT_COG09_TD_DEC11.zip
	wget -P data/2009 https://www.oecd.org/pisa/pisaproducts/INT_COG09_S_DEC11.zip

	# 2012
	wget -P data/2012 https://www.oecd.org/pisa/pisaproducts/INT_STU12_DEC03.zip
	wget -P data/2012 https://www.oecd.org/pisa/pisaproducts/INT_SCQ12_DEC03.zip
	wget -P data/2012 https://www.oecd.org/pisa/pisaproducts/INT_PAQ12_DEC03.zip
	wget -P data/2012 https://www.oecd.org/pisa/pisaproducts/INT_COG12_DEC03.zip
	wget -P data/2012 https://www.oecd.org/pisa/pisaproducts/INT_COG12_S_DEC03.zip

	# 2015
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_STU_QQQ.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_SCH_QQQ.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_TCH_QQQ.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_STU_COG.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_STU_QTM.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CM2_STU_QQQ_COG_QTM_SCH_TCH.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_STU_FLT.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_COMBINED_CMB_STU_CPS.zip
	wget -P data/2015 https://webfs.oecd.org/pisa/PUF_SPSS_STU_TTM.zip

	# 2018
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_STU_QQQ.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_SCH_QQQ.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_TCH_QQQ.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_STU_COG.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_QMC_ALLDB.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_STU_TIM.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_VNM_PV_COG.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_STU_FLT.zip
	wget -P data/2018 https://webfs.oecd.org/pisa2018/SPSS_STU_TTM.zip

	# 2022
	wget -P data/2022 https://webfs.oecd.org/pisa2022/SCH_QQQ_SPSS.zip
	wget -P data/2022 https://webfs.oecd.org/pisa2022/STU_QQQ_SPSS.zip
	wget -P data/2022 https://webfs.oecd.org/pisa2022/TCH_QQQ_SPSS.zip
	wget -P data/2022 https://webfs.oecd.org/pisa2022/STU_COG_SPSS.zip
	wget -P data/2022 https://webfs.oecd.org/pisa2022/STU_TIM_SPSS.zip

	# ESCS
	wget -P data/escs_trend https://webfs.oecd.org/pisa/trend_escs_SAS.zip
	wget -P data/escs_trend https://webfs.oecd.org/pisa/trend_escs_SPSS.zip
	wget -P data/escs_trend https://webfs.oecd.org/pisa2022/escs_trend.zip
