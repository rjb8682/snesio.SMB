cd $1/genomes
ls -al > filenames
python3 ../../filenames_to_csv.py $1
cd ../..
