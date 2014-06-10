#!/usr/bin/env bash

#test for help flag
if [ $1 == '-h' ]
then
    echo "usage: $0 source_loc num_samples [-AD] [-AR]"
    exit
fi

set -eu
set -o pipefail
#Use date and time as a signature for the generated data
sig=`date +%F-%H-%M-%S`
#sge stuff
memory=10G
processors=1
logdir=~/sge_logs/gen_exomise/$sig/
mkdir -pv $logdir
out=/dupa-filer/talf/matchingsim/patients/$sig/
data=/dupa-filer/talf/matchingsim/patients
#location of files given first, number of files to generate is given as second argument
loc=$1
num=$2
#step 1: make copies of some files (randomly choose the number specified)
mkdir -pv $out
for s in `ls $loc/*.vcf.gz $loc/*.vcf | sort -R | head -n $num`
do
    cp $s $out 
done
#step 2: run our patient generator to "infect" all of these patients
python $data/randompatients/generate_patients.py $data/phenotype_annotation.tab $data/hgmd_correct.jv.vcf $out $data/orphanet_lookup.xml $data/orphanet_inher.xml $data/orphanet_geno_pheno.xml -I AD
#step 3: create a script and dispatch exomizer job (and create rerun script)
cat > "$out/rerun.sh" <<EOF
for s in $out/scripts/*.sh
do
    qsub -S /bin/sh \$s
done
EOF

mkdir -pv $out/scripts
for file in $out/*.vcf.gz; do
    #create a bash script
    #get only ending to name script
    f=`echo $file | rev | cut -d '/' -f1 | rev | cut -d '.' -f1`
    script="$out/scripts/dispatch_$f.sh"   
    cat > "$script" <<EOF
#!/usr/bin/env bash
#$ -V
#$ -N "$f"
#$ -pe parallel "$processors"
#$ -l h_vmem="$memory"
#$ -e $logdir
#$ -o $logdir

set -eu
set -o pipefail
temp=\$TMPDIR/$f.ezr

#Run exomizer, only if the required file doesn't already exist
if [ ! -f "$out"/$f.ezr ]
then
    gunzip $out/$f.vcf.gz
    java -Xmx1900m -Xms1000m -jar /data/Exomiser/Exomizer.jar --db_url jdbc:postgresql://combine-102.biolab.sandbox/nsfpalizer -D /data/Exomiser/ucsc.ser -I AD -F 1 --hpo_ids `cat $out/"$f"_hpo.txt` -v $out/$f.vcf --vcf_output -o \$temp
fi

mv -v \$temp $out/$f.ezr.temp
mv -v $out/$f.ezr.temp $out/$f.ezr
EOF
    #Submit
    qsub -S /bin/sh "$script"

done
