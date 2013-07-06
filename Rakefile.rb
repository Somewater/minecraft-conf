require 'fileutils'

namespace :sync do
  desc "Sync worlds from server"
  task :from do
    executable = 'rsync'
    args = ['-r', '--progress', '--human-readable']
    src = 'atlantor.ru:minecraft/worlds'
    dest = '.' 
    puts (exec "#{executable} #{args.join(' ')} #{src} #{dest}")
  end
end

namespace :java do
  desc "Compile plugin <name>"
  task :compile, [:classname] do |task, args|
    class_name = args['classname']
    plugin_name = class_name.downcase
    puts "Start compiling #{class_name}"
    FileUtils.mkdir_p "target/#{plugin_name}"
    status = %x[javac -cp libs/*.jar -g -Xlint:unchecked -d target/#{plugin_name} -sourcepath src/main/java/ src/main/java/com/hellespontus/plugins/#{class_name}.java]
    if status.to_s.size == 0
      puts "[ok] compiling"
    else
      puts "COMPILE ERROR\n#{status}"
    end
    status = %x[jar cf plugins/#{plugin_name}.jar -C target/#{plugin_name} . -C src/main/resources/#{plugin_name} .]
    if status.to_s.size == 0
      puts "[ok] archiving"
    else
      puts "ARCHIVING ERROR\n#{status}"
    end
  end
end