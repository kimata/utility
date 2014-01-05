#!/usr/bin/env ruby

######################################################################
# This script executes two tasks.
# 1. adjust photo directory structure as below
#     +- YYMMDD_title (*.jpg files)
#     |  +- raw (*.crs files)
#    +- YYMMDD_title
#     |  + raw
#     :
#
# 2. remove raw file if JPEG file with same name does not exist 
######################################################################

require 'find'
require 'pathname'
require 'fileutils'
require 'optparse'
require "readline"
require "date"

RAW_DIR_NAME = "raw"

OPT = {}

def mkdir(path)
  puts "    make dir #{path}"
  FileUtils.mkdir_p(path, {:noop => OPT[:dry_run]})
end

def move(from, to)
  puts "    move     #{from} -> #{to}"
  raise "item already exists: #{to}" if File.exists?(to)
  FileUtils.mv(from, to, {:noop => OPT[:dry_run]})
end

def remove(path)
  puts "    remove   #{path}"
  FileUtils.rm(from, {:noop => OPT[:dry_run]})
end

def get_file_list(path, ext_list)
  file_list = []
  Find.find(path) {|f|
    next if File.directory?(f)
    ext_list.each {|ext| 
      file_list.push(f) if f =~ /\.#{ext}$/i
    }
  }
  return file_list
end

def remove_raw(base, path)
  if OPT[:trash_path] != nil then
    rel_path = Pathname.new(path).relative_path_from(Pathname.new(base))
    move_path = Pathname.new(OPT[:trash_path]).join(rel_path)

    mkdir(move_path.dirname) unless File.exists?(move_path.dirname)
    move(path, move_path)
  else

  end
end

def clean_failed_raw(base, path, raw_list, jpeg_name_list)
  raw_list.each {|raw_file|
    is_jpeg_exists = false
    raw_name = File.basename(raw_file, ".*")

    jpeg_name_list.each {|jpeg_name|
      if jpeg_name == raw_name then
        is_jpeg_exists = true
      end
    }

    if is_jpeg_exists then
      puts "    \033[90;1mkeep     #{raw_file}\033[0m" if OPT[:verbose]
    else
      remove_raw(base, raw_file) unless is_jpeg_exists
    end
  }
end

def parse_dir_name(sub_dir_name)
  case sub_dir_name
  when /^(\d{4})[-_](\d{2})[-_](\d{2})$/
    return {
      :norm_name => sprintf("%02d%02d%02d_", $~[1].to_i - 2000, $~[2].to_i, $~[3].to_i),
      :time => Time.local($~[1].to_i, $~[2].to_i, $~[3].to_i)
    }
  when /^(\d{2})(\d{2})(\d{2})_.*$/
    return {
      :norm_name => sub_dir_name,
      :time => Time.local(2000 + $~[1].to_i, $~[2].to_i, $~[3].to_i)
    }
  else
    return nil
  end
end

def normalize_raw_path(base, path, raw_list)
  raw_dir_path = Pathname.new(path).join(RAW_DIR_NAME)
  mkdir(raw_dir_path) unless File.exists?(raw_dir_path)
  raw_list.each {|raw_file|
    org_raw_path = Pathname.new(raw_file)
    new_raw_path = raw_dir_path.join(Pathname.new(raw_file).basename())
    
    next if org_raw_path == new_raw_path
    raise "file already exists: #{new_raw_path}" if File.exists?(new_raw_path)

    move(org_raw_path, new_raw_path)
  }
end

def normalize_dir_path(path)
  dir_info = parse_dir_name(File.basename(path))
  if dir_info == nil then
    puts "    \033[93;1m[WARN] UNEXPECT DIRECTORY NAME\033[0m"
    return
  end

  File::utime(dir_info[:time], dir_info[:time], path)

  if dir_info[:norm_name] != File.basename(path) then
    new_path = File.join(File.dirname(path), dir_info[:norm_name])
    if File.exists?(new_path) then
      puts "    \033[93;1m[WARN] SAME DIRECTORY ALREADY EXISTS\033[0m"
    end
    move(path, new_path)
  end
end

def clean_sub_dir(base, path)
  puts "\033[32;1m*CLEAN subdir\t#{path}\033[0m"
  
  jpeg_list = get_file_list(path, ["jpg", "jpeg"]);
  mov_list = get_file_list(path, ["mov"]);
  raw_list = get_file_list(path, ["cr2"]);

  if (jpeg_list.count == 0) && (mov_list.count == 0) then
    puts "    \033[93;1m[WARN] NO JPEG/MOV FOUND\033[0m"
    return
  end
  
  jpeg_name_list = jpeg_list.map {|file| File.basename(file, ".*") }

  # TASK1
  clean_failed_raw(base, path, raw_list, jpeg_name_list)
  # TASK2
  normalize_raw_path(base, path, raw_list)
  # TASK3
  normalize_dir_path(path)
end

def clean_dir(path)
  puts "\033[34;1m*CLEAN*\t\t#{path}\033[0m"
  Find.find(path) {|d|
    dir_name = File.basename(d)
    next if dir_name == "."
    next if File.file?(d)
    Find.prune if dir_name =~ /^\./

    clean_sub_dir(path, d)

    Find.prune
  } 
end

opt = OptionParser.new
opt.on('-D', '--dry-run') {|v| OPT[:dry_run] = v }
opt.on('-T TRASH_PATH', '--trash TRASH_PATH') {|v| OPT[:trash_path] = v }
opt.on('-v', '--verbose') {|v| OPT[:verbose] = v }
opt.permute!(ARGV)

if OPT[:trash_path] == nil then
  answer = Readline.readline("\033[33;1mTRASH_PATH is NOT set. OK?\033[0m [y/N] ")
  exit unless answer =~ /^Y/i
end

ARGV.each {|dir|
  clean_dir(dir)
}
