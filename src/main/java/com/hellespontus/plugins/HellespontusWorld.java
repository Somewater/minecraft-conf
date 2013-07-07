package com.hellespontus.plugins;

import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

public class HellespontusWorld extends JavaPlugin implements Listener{
    Logger log = Logger.getLogger("Minecraft");
    List<Area> unbreakable;
    Map<String, Vector> points;

    public void onEnable(){
        getServer().getPluginManager().registerEvents(this, this);
        
        List<Integer> worldSpawnPoint = getConfig().getIntegerList("world_spawnpoint");
        getServer().getWorld("world").setSpawnLocation(worldSpawnPoint.get(0), worldSpawnPoint.get(1), worldSpawnPoint.get(2));
        
        unbreakable = new ArrayList<Area>();
        for(Object obj : getConfig().getList("unbreakable")){
            @SuppressWarnings("unchecked")
            List<Integer> point = (List<Integer>) obj;
            Area area = new Area();
            area.point = new Vector(point.get(0), point.get(1), point.get(2));
            if(point.size() > 3)
                area.radius = point.get(3);
            unbreakable.add(area);
        }
        
        points = new HashMap<String, Vector>(10);
        getCommand("point").setExecutor(new PointCommandExecutor());
    }

    public void onDisable(){
        
    }
    
    @EventHandler
    public void onBlockBreak(BlockBreakEvent event){
        Vector location = event.getBlock().getLocation().toVector();
        for(Area area : unbreakable)
            if(area.point.distance(location) < area.radius){
                event.getPlayer().sendMessage("Block break cancelled. Unbreakable point " + 
                    area.point.toString() + ", dist= " + Math.round(area.point.distance(location)) + "/" + area.radius);
                event.setCancelled(true);
                break;
            }
    }

    private class PointCommandExecutor implements CommandExecutor {
        @Override
        public boolean onCommand(CommandSender commandSender, Command command, String s, String[] strings) {
            if(!(commandSender instanceof Player)){
                commandSender.sendMessage("Only online players can invoke this command");
                return true;
            }
            Vector point = ((Player) commandSender).getLocation().toVector();
            Vector lastPoint = points.get(commandSender.getName().toLowerCase());
            StringBuilder msg = new StringBuilder("Point: [" + point.getBlockX() + ", " + point.getBlockY() + ", " + point.getBlockZ() + "]");
            if(lastPoint != null){
                msg.append("   Distance: " + Math.round(lastPoint.distance(point)));
            }
            commandSender.sendMessage(msg.toString());
            points.put(commandSender.getName().toLowerCase(), point);
            return true;
        }
    }
    
    private static class Area{
        public Vector point;
        public int radius = 10;
    }
}
