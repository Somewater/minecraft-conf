package com.hellespontus.plugins;

import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.Sound;
import org.bukkit.entity.EntityType;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockDamageEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.List;
import java.util.logging.Logger;

public class HelloWorld extends JavaPlugin implements Listener{
    Logger log = Logger.getLogger("Minecraft");
    List<Vector> unbreakable;

    public void onEnable(){
        getServer().getPluginManager().registerEvents(this, this);
        
        List<Integer> worldSpawnPoint = getConfig().getIntegerList("world_spawnpoint");
        getServer().getWorld("world").setSpawnLocation(worldSpawnPoint.get(0), worldSpawnPoint.get(1), worldSpawnPoint.get(2));
        
        unbreakable = new ArrayList<Vector>();
        for(Object obj : getConfig().getList("unbreakable")){
            @SuppressWarnings("unchecked")
            List<Integer> point = (List<Integer>) obj;
            unbreakable.add(new Vector(point.get(0), point.get(1), point.get(2)));
        }
    }

    public void onDisable(){
        
    }
    
    @EventHandler
    public void onBlockBreak(BlockBreakEvent event){
        Vector location = event.getBlock().getLocation().toVector();
        int R = 100;
        for(Vector point : unbreakable)
            if(point.distance(location) < R){
                event.setCancelled(true);
                break;
            }
    }

    @EventHandler
    public void onBlockDamage(BlockDamageEvent event){
        getServer().broadcastMessage("Location: " + event.getBlock().getLocation().toString());
    }
}
