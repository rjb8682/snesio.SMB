cd $1
cd genomes
ls -al > filenames
python3 ../../filenames_to_csv.py
cd ../..
