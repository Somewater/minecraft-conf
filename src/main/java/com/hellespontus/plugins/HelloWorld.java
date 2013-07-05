package com.hellespontus.plugins;

import org.bukkit.Material;
import org.bukkit.Sound;
import org.bukkit.entity.EntityType;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.logging.Logger;

public class HelloWorld extends JavaPlugin implements Listener{
    Logger log = Logger.getLogger("Minecraft");

    public void onEnable(){
        getServer().getPluginManager().registerEvents(this, this);
    }

    public void onDisable(){
        
    }
    
    @EventHandler
    public void onBlockBreak(BlockBreakEvent event){
        if (event.getBlock().getType() == Material.GLASS) {
            event.getPlayer().playSound(event.getBlock().getLocation(), Sound.SPIDER_WALK, 1, 1);
            event.getBlock().getLocation().getWorld().spawnEntity(event.getBlock().getLocation(), EntityType.BAT);
        }
    }
}
