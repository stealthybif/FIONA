#!/bin/bash 

####
# importPhilipskspace.sh will 
#    1) Go into $kspacedir (/data/site/k-space-data-store)
#    2) Create list of directories found there with the NDAR prefix
#    3) Create tgz, json, and md5sum files for each Series with the following naming scheme: SUID_<StudyInstanceUID>_subjid_<PatientName>_<SeriesInstanceUID>_se<SeriesNumber>_<date>_<time>
#    4) Move tgz, json, and md5sum files to quarantine
#    5) Delete original NDAR directory in /data/k-space-data-store when finished.
#
# Assumptions:
#    1) Reconstructed DICOM Data has already been pushed from FIONA to DAIC through web-interface
#    2) Raw kspace data independently been transferred from scanner console to FIONA path $kspacedir (/data/site/k-space-data-store)
#              a) $kspacedir must be organized as follows:
#					/data/site/k-space-data-store
#							-> NDAR_INV0000001/
#								-> subject .raw,.sin, .lab,  and .cpx files
#							-> NDAR_INV0000002/
#								-> subject .raw,.sin, .lab,  and .cpx files
####

#####
#Adjust paths here, if needed
kspacedir=/data/site/k-space-data-store
daicdir=/data/DAIC
rawdir=/data/site/raw
tdir=/tmp/$$
#############

###############
#Create temporary dir for deletion later
echo "TEMPDIR: ${tdir}"
mkdir ${tdir}
###############

###############
#Create list from subject found in $kspacedir
cd ${kspacedir}
ls -d NDAR* > ${tdir}/subjectlist
###############

###############
#Create list of subjects found in $rawdir json files to $tmpfile
cd ${rawdir}
tmpfile=$(mktemp ${tdir}/abcd-rawlist.XXXXXX)                                    
jq -r "[.PatientName,.PatientID,.StudyInstanceUID,.SeriesInstanceUID,.SeriesNumber] | @csv" */*.json > ${tmpfile} 
###############

###############
#Loop through Subjects found in subjeclist
for PatientName in `cat ${tdir}/subjectlist`
do

   #Proceed only if subject is found in both the subjectlist and $tmpfile
   if cat ${tmpfile} | grep ${PatientName} &> /dev/null; then
      echo "Working on: ${PatientName}"
      #Loop through $tmpfile json for each Subject
      for json in `cat ${tmpfile} | grep ${PatientName}`
      do
          StudyInstanceUID=`echo ${json} | awk -F'"' '{print $6}'`
	      SeriesInstanceUID=`echo ${json} | awk -F'"' '{print $8}'`
	      SeriesNumber=`echo ${json} | awk -F'"' '{print $10}'`
	      
          #Extract Date/Time string
          dt=`echo ${SeriesInstanceUID} | awk -F'.' '{print $10}'`
          
          #Date, in 2 forms
	      d=`echo ${dt} | cut -c 1-8 | xargs date  +%Y%m%d -d`          
	      d2=`echo ${d} | xargs date +%m-%d-%Y -d`
	      
          #Time	
          t=`echo ${dt} | cut -c 9-14`
          	  	  
	  	  #################
	  	  # Philips kspace files are in the format
	  	  #				<date>_<time>_<series name type>.raw  They are accompanied with .sin, .lab files as well
	  	  #				e.g.   20170225_11829_113050_3D_T1.raw
	  	  #		NOTE: The correct CoilSurvey and SenseRef files need to be bundled with each series.
	  	  #					coca = SenseRef. coil = CoilSurvey. Coilsurvey is only found in DTI. SenseRef is part of all scans.
	  	  #################
          #If Date/Time is matches filename in $kspacedir then bundle files into tgz file
          if ls ${kspacedir}/${PatientName}/*${d}*${t}* &> /dev/null; then
            	#Build filename
	        	fn=SUID_${StudyInstanceUID}_subjid_${PatientName}_${SeriesInstanceUID}_se${SeriesNumber}_${d2}_${t}
          		echo "Create TGZ now: ${fn}.tgz"
          		if hash pigz 2>/dev/null; then
          			cd ${kspacedir}/${PatientName}
          			file=`echo *${d}*${t}*.raw`
          			echo ${file}
          			# 
          			if cat ${file%.*}.sin | grep coil_survey_cpx_file_names &>/dev/null; then 
          				coil=`cat ${file%.*}.sin | grep coil_survey_cpx_file_names | cut -d':' -f3  | cut -d '.' -f1`
                		coca=`cat ${file%.*}.sin | grep coca_cpx_file_names | cut -d':' -f3  | cut -d '.' -f1`
                		echo "Bundling $coca and $coil into ${fn} tgz..."
                		tar cf - *${d}*${t}* ${coca}* ${coil}* | pigz --fast -p 6 > ${tdir}/${fn}.tgz
          				md5sum ${tdir}/${fn}.tgz  > ${tdir}/${fn}.md5sum
          				echo "{ \"PatientName\": \"$PatientName\", \"SeriesInstanceUID\": \"${SeriesInstanceUID}\", \"StudyInstanceUID\": \"${StudyInstanceUID}\", \"dat\": \"${file}\", \"type\": \"Philips k-space\" }" > ${tdir}/${fn}.json
          				mv ${tdir}/${fn}* /data/quarantine
	  					packval=$?
	  				else
	  					coca=`cat ${file%.*}.sin | grep coca_cpx_file_names | cut -d':' -f3  | cut -d '.' -f1`
	  					echo "Bundling $coca into ${fn} tgz..."
	  					tar cf - *${d}*${t}* ${coca}* | pigz --fast -p 6 > ${tdir}/${fn}.tgz
          				md5sum ${tdir}/${fn}.tgz  > ${tdir}/${fn}.md5sum
          				echo "{ \"PatientName\": \"$PatientName\", \"SeriesInstanceUID\": \"${SeriesInstanceUID}\", \"StudyInstanceUID\": \"${StudyInstanceUID}\", \"dat\": \"${file}\", \"type\": \"Philips k-space\" }" > ${tdir}/${fn}.json
          				mv ${tdir}/${fn}* /data/quarantine
	  					packval=$?
	  				fi
      	  		else
	  				GZIP=-1 tar cvzf ${tdir}/${fn}.tgz *${d}*${t}*
	  				mv ${tdir}/${fn}* /data/quarantine
	  				packval=$?
		  		fi
		  		if [ $packval -ne 0 ]; then
	  				# something went wrong, remove this output, if it exists
	  				echo "   ERRROR: could not create tar file ${fn}"
	  				if [ -e "${fn}" ]; then
	      			/bin/rm -f "${fn}"
	  				fi
	  				# try again next time
	  			continue
				fi
		  else 
		  		echo "No series matching date and time, ${d} ${t}. Moving on to next date/time"
          fi
          cd -
      done
   fi
   ##############
   # Cleanup $kspacedir
   # For now move subject to 'transferred' subdir. Later on, change this to rm
   mv ${kspacedir}/${PatientName} ${kspacedir}/transferred
done

#############
#Cleanup $tdir
rm -R ${tdir}
