###### Docker extensions #######
__docker_containers_all_standalone() { cur="$2"; __docker_containers_all; }

alias dlogs='docker logs --tail=25 -f'
complete -F __docker_containers_all_standalone dlogs

dps() {
	(
		#echo -e "State^Name^IP^Image^Status^Restart^Ports\n---^---^---^---^---^---"
		local GREEN="[1;32m"
		local RED="[1;31m"
		local GRAY="[1;30m"
		local RESET="[0m"
		docker ps -a --format "{{.ID}}^{{.Status}}" | while read line; do
			ID="${line%%^*}"
			STATUS="${line##*^}"
			docker inspect --format="{{if .State.Running}}${GREEN}Running{{else}}${RED}{{end}}\
^{{.Name}}\
^{{.NetworkSettings.IPAddress}}\
^{{.Config.Image}}\
^$STATUS\
^{{.HostConfig.RestartPolicy.Name}}\
^{{range \$key, \$value := .NetworkSettings.Ports}}\
{{if .}}\
{{if or (eq (printf \"%s/tcp\" (index . 0).HostPort) \$key) (eq (printf \"%s/udp\" (index . 0).HostPort) \$key)}}\
${GREEN}{{\$key}}\
{{else}}\
${RED}{{\$key}}->{{(index . 0).HostPort}}\
{{end}}\
{{else}}${GRAY}{{\$key}}{{end}}\
${RESET} {{end}}${RESET}" "$ID"
		done | sort -t "^" -k 2
	) | column -tns "^"
}

dbash() { docker exec -it $1 /bin/bash; }
complete -F __docker_containers_all_standalone dbash

alias dip='docker inspect --format="{{.NetworkSettings.IPAddress}}"'
complete -F __docker_containers_all_standalone dip

alias dstats='docker stats $(docker inspect --format "{{.Name}}" `docker ps -q`)'

alias dcleanc='docker rm `docker ps -f status=exited -q`'
alias dcleani='docker rmi `docker images -f dangling=true -q`'

dinfo() {
	ruby <<EndOfRuby
		require 'json'
		CONTAINER = "$1"
		RED="\x1B[1;31m"
		GREEN="\x1B[1;32m"
		GRAY="\x1B[1;30m"
		RESET="\x1B[m"
		begin
			jsonc = JSON.parse(%x[docker inspect #{CONTAINER}]).first
			jsoni = JSON.parse(%x[docker inspect #{jsonc["Image"]}]).first
		rescue
			puts "Den gesuchten Container #{CONTAINER} gibt es anscheinend nicht."
			exit 1
		end
		
		cmd = "docker run"
		data = []
		
		data << ["Name:", jsonc["Name"][1..-1]]
		cmd << " --name #{jsonc["Name"][1..-1]}"
		data << ["ID:", GRAY+jsonc["Id"]+RESET]
		data << ["Privileged:", jsonc["HostConfig"]["Privileged"].to_s]
		cmd << " --privileged" if jsonc["HostConfig"]["Privileged"]
		rpol = jsonc["HostConfig"]["RestartPolicy"]["Name"]
		retrystring = (rpol=="on-failure" ? ":#{jsonc["HostConfig"]["RestartPolicy"]["MaximumRetryCount"]}" : "")
		data << ["Restart:", rpol + retrystring]
		cmd << " --restart=#{rpol}#{retrystring}" unless rpol=="no"
		data << ["IP Address:", jsonc["NetworkSettings"]["IPAddress"]]
		
		data << ["", ""]
		
		temp = jsonc["Config"]["Cmd"].join(" ") rescue ""
		temp = "#{GRAY}#{temp}#{RESET}" if jsonc["Config"]["Cmd"]==jsoni["Config"]["Cmd"]
		data << ["Command:", temp]
		temp = jsonc["Config"]["Entrypoint"].join(" ") rescue ""
		temp = "#{GRAY}#{temp}#{RESET}" if jsonc["Config"]["Entrypoint"]==jsoni["Config"]["Entrypoint"]
		data << ["Entrypoint:", temp]
		
		
		data << ["", ""]
		
		env = []
		(jsonc["Config"]["Env"] || []).each do |e|
			if jsoni["Config"]["Env"].include?(e)
				env << ["#{GRAY}#{e}#{RESET}"]
			else
				env << [e]
				cmd << " -e #{e}"
			end
		end
		data << ["Environment:", env]
		
		data << ["", ""]
		
		binds = []
		(jsonc["HostConfig"]["Binds"] || []).each do |b|
			parts = b.split(":")
			parts << nil if parts.count==2
			binds << parts
			cmd << " -v #{b}"
		end
		data << ["Binds:", binds]
		
		data << ["", ""]
		
		ports = []
		(jsonc["NetworkSettings"]["Ports"] || []).each do |p,target|
			port, protocol = *p.split("/")
			if target
				col = (port == target[0]["HostPort"] ? GREEN : RED)
				ports << ["#{col}#{port}#{protocol=="tcp" ? "" : "/#{protocol}"}", ("#{target[0]["HostIp"]=="0.0.0.0" ? "" : target[0]["HostIp"]+":"}#{target[0]["HostPort"]}" rescue "")+RESET]
				cmd << " -p #{target[0]["HostPort"]}:#{target[0]["HostIp"]=="0.0.0.0" ? "" : target[0]["HostIp"]+":"}#{port}"
			else
				ports << ["#{GRAY}#{port}#{protocol=="tcp" ? "" : "/#{protocol}"}#{RESET}", nil]
			end
		end
		data << ["Ports:", ports]
		
		data << ["", ""]
		
		links = []
		(jsonc["HostConfig"]["Links"] || []).each do |link|
			source, target = *link.split(":")
			source = source[1..-1]
			target = target.split("/").last
			links << [source, target==source ? "#{GRAY}#{target}#{RESET}" : target]
			cmd << " --link #{source}#{target!=source ? ":"+target : ""}"
		end
		data << ["Links:", links]
		
		data << ["", ""]
		
		labels = []
		(jsonc["Config"]["Labels"] || []).each do |key, value|
			labels << [key, value]
			cmd << " --label=\"#{key}=#{value}\""
		end
		data << ["Labels:", labels]
		
		data << ["", ""]
		
		cmd << " " + jsonc["Config"]["Image"]
		
		cmd << " "+jsonc["Config"]["Cmd"].join(" ") unless jsonc["Config"]["Cmd"]==jsoni["Config"]["Cmd"]
		
		data << ["Command:", cmd]
		
		width = data.collect(&:first).collect(&:length).max
		data.each do |entry|
			print " %#{width}s " % entry[0]
			if entry[1].is_a?(String)
				puts entry[1]
			elsif entry[1].nil? || entry[1]==[]
				puts "---"
			else
				first_row = true
				widths = entry[1].collect{|array| array.collect{|v| v.length rescue 0}}.transpose.collect{|a| a.max}
				entry[1].each do |row|
					print " %#{width}s " % "" unless first_row
					row.each_with_index do |value, index|
						print "%-#{widths[index]}s " % value
					end
					puts ; first_row = false
				end
			end
		end
		
EndOfRuby
}
complete -F __docker_containers_all_standalone dinfo

dversions() {
	ruby << EndOfRuby
		require 'json'
		require 'open-uri'
		IMAGE = "$1"
		data = JSON.parse(open("https://registry.hub.docker.com/v1/repositories/#{IMAGE}/tags").read)
		tags = Hash.new{[]}
		data.each{|hash| tags[hash["layer"]] += [hash["name"]]}
		tags.each{|key,value| puts value.join(", ")}
EndOfRuby
}

dhelp() {
	echo "Extended docker commands"
	echo "By Fabian Schlenz <mail@fabianonline.de>"
	echo
	echo "dbash <CONTAINER>     Short for 'docker exec -it <CONTAINER> /bin/bash'."
	echo "dcleanc               Removes all stopped containers."
	echo "dcleani               Removes all dangling images."
	echo "dinfo <CONTAINER>     Shows some information about a certain container."
	echo "dip                   Shows the IP Address of the last run container."
	echo "dlogs <CONTAINER>     Short for 'docker logs --tail=25 -f <CONTAINER>'."
	echo "dps                   Better display of all containers."
	echo "dstats                Like 'docker stats' but with container names."
	echo
	echo "To be done:"
	echo "dupdate <IMAGE>       Update an image by pulling the most recent version."
	echo "dversions <IMAGE>     List available tags for IMAGE."
}
